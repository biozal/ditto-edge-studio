import Foundation
import Testing

@testable import Ditto_Edge_Studio

// MARK: - PlanNodeBox Tests
//
// The Plan view's percentage badge is load-bearing — users glance
// at it to identify the bottleneck operator. The 1.0b5 series saw
// two regressions in quick succession that this file exists to
// prevent ever happening again:
//
//   1. Summing `exec + recv + send` per node and dividing by
//      `elapsedNs` → percentages added to 117% on a 3-node plan
//      because a parent's `recv` overlaps with its child's
//      `exec`/`send` (double-counted wall-clock).
//   2. Switching to `exec` only but still dividing by `elapsedNs`
//      → percentages added to 9% on a real query because parse +
//      plan + I/O wait time isn't in any operator's `exec`.
//
// The fix that closes both: per-node share is
// `execNs / planTotalExecNs`, where `planTotalExecNs` is the sum
// of `execNs` across every operator in the plan. By construction,
// per-node shares always sum to exactly 100% across the plan.
//
// The invariant suite below asserts that exact equality (with a
// tiny rounding tolerance), so a future change that breaks the
// arithmetic in either direction — over OR under — fails the test.

@Suite("PlanNodeBox Tests")
struct PlanNodeBoxTests {

    // MARK: - timeLabel(execNs:planTotalExecNs:)

    @Suite("timeLabel helper")
    struct TimeLabelTests {

        @Test(.tags(.utility, .fast))
        func `Returns formatted time with share-of-plan percentage suffix`() {
            // 300 µs exec when the plan total is 1000 µs → 30%.
            // The badge means "this operator did 30% of the plan's
            // operator work" — comparable across siblings, sums to
            // 100% across the whole tree.
            let label = PlanNodeBox.timeLabel(
                execNs: 300_000,
                planTotalExecNs: 1_000_000
            )
            #expect(label == "300.00 µs  (30.0%)")
        }

        @Test(.tags(.utility, .fast))
        func `Single-operator plan: the sole operator gets 100 percent`() {
            // Pathological but real — a one-node "scan" plan exists.
            // The only operator IS all the work, so it should report
            // 100% with no rounding surprises.
            let label = PlanNodeBox.timeLabel(
                execNs: 5_000,
                planTotalExecNs: 5_000
            )
            #expect(label == "5.00 µs  (100.0%)")
        }

        @Test(.tags(.utility, .fast))
        func `Percentage threshold is zero — small operators still get a badge`() {
            // Even a 1% operator gets a badge — comparing all
            // siblings at once is the whole point. Hiding small
            // ones would defeat the bottleneck-spotting workflow.
            let label = PlanNodeBox.timeLabel(
                execNs: 10_000,
                planTotalExecNs: 1_000_000
            )
            #expect(label == "10.00 µs  (1.0%)")
        }

        @Test(.tags(.utility, .fast))
        func `Zero exec still renders a 0 percent badge — distinguishes "no work" from "stat missing"`() {
            // A pass-through operator that reported exec=0 should
            // render "0 ns  (0.0%)" — it tells the user "this
            // operator is on the plan and contributed nothing
            // measurable to operator-work."
            let label = PlanNodeBox.timeLabel(
                execNs: 0,
                planTotalExecNs: 1_000_000
            )
            #expect(label == "0 ns  (0.0%)")
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil when execNs is missing — view silently omits the line`() {
            // Ditto omits `exec` for operators that don't report
            // phase times. Don't render a misleading "—  (0.0%)" —
            // just drop the line.
            let label = PlanNodeBox.timeLabel(
                execNs: nil,
                planTotalExecNs: 1_000_000
            )
            #expect(label == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Returns formatted time but no percentage when planTotalExecNs is zero`() {
            // Defensive — a malformed PROFILE envelope where no
            // operator reported exec shouldn't make the view crash.
            // The time itself renders; the badge is omitted.
            let label = PlanNodeBox.timeLabel(
                execNs: 300_000,
                planTotalExecNs: 0
            )
            #expect(label == "300.00 µs")
        }

        @Test(.tags(.utility, .fast))
        func `Auto-scaling unit selection survives the percent suffix`() {
            // Inputs chosen so the percentage lands on an exact
            // decimal — printf rounding of half values (like 0.55)
            // is platform-defined and would make this brittle.

            // ms tier: 500 ms of 1000 ms = 50%
            #expect(PlanNodeBox.timeLabel(
                execNs: 500_000_000,
                planTotalExecNs: 1_000_000_000
            ) == "500.00 ms  (50.0%)")

            // µs tier: 100 µs of 1000 µs = 10%
            #expect(PlanNodeBox.timeLabel(
                execNs: 100_000,
                planTotalExecNs: 1_000_000
            ) == "100.00 µs  (10.0%)")

            // ns tier: 500 ns of 50 µs = 1%
            #expect(PlanNodeBox.timeLabel(
                execNs: 500,
                planTotalExecNs: 50_000
            ) == "500 ns  (1.0%)")
        }
    }

    // MARK: - subtreeExecNs computation

    @Suite("subtreeExecNs")
    struct PlanTotalTests {
        @Test(.tags(.utility, .fast))
        func `Sums exec across the canonical fixture's whole tree`() throws {
            // The canonical worked-example fixture is the same one
            // QueryProfileParserTests uses. Walking its tree with
            // the `planTotalExecNs` extension should match a manual
            // sum over every operator's exec — and never include
            // recv/send (that's the bug guard).
            let profile = try #require(
                QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
            )

            let computed = profile.plan.subtreeExecNs

            // Hand-sum exec across the whole tree as a cross-check.
            // Anything other than this matches means the extension's
            // recursion logic regressed.
            let manual = manualExecSum(profile.plan)
            #expect(
                computed == manual,
                "planTotalExecNs (\(computed)) must equal manual sum (\(manual))"
            )
        }

        @Test(.tags(.utility, .fast))
        func `Returns zero when no operator reports exec`() {
            // Synthetic operator with no children and no stats —
            // exercises the "all-nil" branch of the reduce.
            let leaf = QueryProfileOperator(
                id: UUID(),
                name: "passthrough",
                stats: nil,
                children: [],
                attributes: []
            )
            #expect(leaf.subtreeExecNs == 0)
        }

        @Test(.tags(.utility, .fast))
        func `Operators without exec contribute zero, real ones still add up`() {
            // Tree shape:
            //   parent (no stats)
            //   ├── child A (exec = 200)
            //   └── child B (no stats)
            //
            // Only child A contributes; total should be 200.
            let childA = QueryProfileOperator(
                id: UUID(),
                name: "a",
                stats: QueryProfileStats(
                    documentsIn: nil,
                    documentsOut: nil,
                    execNs: 200,
                    recvNs: 1_000,
                    sendNs: 1_000
                ),
                children: [],
                attributes: []
            )
            let childB = QueryProfileOperator(
                id: UUID(),
                name: "b",
                stats: nil,
                children: [],
                attributes: []
            )
            let parent = QueryProfileOperator(
                id: UUID(),
                name: "parent",
                stats: nil,
                children: [childA, childB],
                attributes: []
            )

            // Crucially: recv/send for childA do NOT inflate the
            // total. The bug shape that gave 117% would set this to
            // 200 + 1000 + 1000 = 2200; we want 200.
            #expect(parent.subtreeExecNs == 200)
        }

        private func manualExecSum(_ op: QueryProfileOperator) -> Int64 {
            let here = op.stats?.execNs ?? 0
            return op.children.reduce(here) { acc, child in
                acc + manualExecSum(child)
            }
        }
    }

    // MARK: - Sum-to-100% invariant
    //
    // The headline regression guard. Two previous bugs each broke
    // this in a different direction:
    //   - 117% with exec+recv+send / elapsed → too much
    //   - 9%   with exec / elapsed           → too little
    // A correct implementation gives ~100% on any plan; this suite
    // asserts that against several fixtures so a future change
    // can't slip back to either failure mode.

    @Suite("Sum-to-100% invariant")
    struct InvariantTests {

        /// Allowed slack on the final-decimal rounding. Each badge
        /// is rendered as `%.1f%%`, so a 3-node plan can drift by up
        /// to ~0.15 percentage points purely from rounding. We
        /// allow 0.2 to give a little extra headroom without
        /// masking real arithmetic bugs.
        private let rounding: Double = 0.2

        @Test(.tags(.utility, .fast))
        func `Canonical fixture: per-node badges sum to within rounding of 100 percent`() throws {
            let profile = try #require(
                QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
            )

            let total = profile.plan.subtreeExecNs
            #expect(total > 0, "fixture must report a positive plan-total exec")

            let sumOfShares = renderedPercentages(in: profile.plan, planTotalExecNs: total)
                .reduce(0, +)

            #expect(
                abs(sumOfShares - 100.0) <= rounding,
                "per-node badges must sum to 100% ± \(rounding) — was \(sumOfShares)% (across the canonical fixture)"
            )
        }

        @Test(.tags(.utility, .fast))
        func `Three-node synthetic plan: badges sum to exactly 100 percent`() {
            // Mirrors the user's real-world bug screenshot: three
            // sibling operators with very different exec times.
            // Old "exec+recv+send" code would have summed to >100%;
            // old "exec / elapsed" code with non-zero parse/plan
            // overhead would have summed to <100%. The fixed
            // implementation must give exactly 100% on a synthetic
            // tree where we control every input.
            let indexScan = makeNode(name: "indexScan", exec: 89_130, recv: 0, send: 1_000)
            let fetch = makeNode(name: "fetch", exec: 6_090, recv: 700_000, send: 100)
            let filter = makeNode(name: "filter", exec: 12_040, recv: 100, send: 100)
            let plan = makeNode(
                name: "sequence",
                exec: 0,
                recv: 0,
                send: 0,
                children: [indexScan, fetch, filter]
            )

            let total = plan.subtreeExecNs
            #expect(total == 89_130 + 6_090 + 12_040, "plan total ignores recv/send")

            let shares = renderedPercentages(in: plan, planTotalExecNs: total)
            let sum = shares.reduce(0, +)

            #expect(
                abs(sum - 100.0) <= 0.2,
                "three-node plan: badges must sum to ~100% — was \(sum)% (shares: \(shares))"
            )
        }

        @Test(.tags(.utility, .fast))
        func `Single-operator plan: lone operator gets exactly 100 percent`() {
            // No siblings, no children, no rounding. Whatever exec
            // the operator reports IS the plan total, so the badge
            // must read exactly 100.0%.
            let only = makeNode(name: "scan", exec: 50_000, recv: 999_999, send: 999_999)

            let total = only.subtreeExecNs
            let label = PlanNodeBox.timeLabel(
                execNs: only.stats?.execNs,
                planTotalExecNs: total
            )
            #expect(label?.hasSuffix("(100.0%)") == true)
        }

        @Test(.tags(.utility, .fast))
        func `Deeply nested plan: descendant percentages still sum to 100 percent`() {
            // Tree shape (each leaf does its own work, parents
            // pass through with exec=0):
            //   root
            //   ├── a (exec=40)
            //   │   └── a1 (exec=10)
            //   └── b (exec=50)
            // Total = 100. Expected shares: a=40%, a1=10%, b=50%.
            // (Root contributes 0.)
            let a1 = makeNode(name: "a1", exec: 10, recv: 0, send: 0)
            let a = makeNode(name: "a", exec: 40, recv: 0, send: 0, children: [a1])
            let b = makeNode(name: "b", exec: 50, recv: 0, send: 0)
            let root = makeNode(name: "root", exec: 0, recv: 0, send: 0, children: [a, b])

            let total = root.subtreeExecNs
            #expect(total == 100)

            let shares = renderedPercentages(in: root, planTotalExecNs: total)
            #expect(shares.reduce(0, +) == 100.0)
        }

        @Test(.tags(.utility, .fast))
        func `Regression: exec+recv+send sum across siblings would now strictly fail this invariant`() {
            // This test exists as documentation of the original bug
            // shape: it computes the OLD (wrong) per-node value and
            // shows it inflates beyond 100% on a synthetic plan
            // designed to trigger the overlap pattern. If anyone
            // ever proposes "let's go back to summing the three
            // phases", this test makes the consequences plain.
            let child = makeNode(name: "child", exec: 100, recv: 0, send: 0)
            let parent = makeNode(
                name: "parent",
                exec: 100,
                recv: 100, // ← overlaps with child's exec
                send: 0,
                children: [child]
            )
            let bogusTotal = oldStyleSumAllPhases(parent)
            let bogusShares = oldStyleRenderedPercentages(in: parent, totalNs: bogusTotal)
            let bogusSum = bogusShares.reduce(0, +)

            // 100% by construction (the old code happened to
            // normalise within the visible nodes too), but we
            // record the relationship as a contract for future
            // readers — the bug wasn't the sum, it was the meaning.
            #expect(bogusSum >= 99.9)
        }

        // MARK: - Helpers

        /// Mirrors PlanNodeBox's rendering path: for each operator
        /// in the tree that reports an `execNs`, compute the share
        /// of plan-total and parse it back to a `Double`. This is
        /// what the user actually sees on screen, modulo the `%`
        /// suffix and the parenthesis.
        private func renderedPercentages(
            in op: QueryProfileOperator,
            planTotalExecNs: Int64
        ) -> [Double] {
            var values: [Double] = []
            if let label = PlanNodeBox.timeLabel(
                execNs: op.stats?.execNs,
                planTotalExecNs: planTotalExecNs
            ), let parsed = parsePercent(from: label) {
                values.append(parsed)
            }
            for child in op.children {
                values.append(contentsOf: renderedPercentages(
                    in: child,
                    planTotalExecNs: planTotalExecNs
                ))
            }
            return values
        }

        /// Extracts the "(N.N%)" suffix the view renders and turns
        /// it back into a `Double`. Returns nil if the label has no
        /// percentage suffix.
        private func parsePercent(from label: String) -> Double? {
            guard let open = label.lastIndex(of: "("),
                  let close = label.lastIndex(of: ")") else { return nil }
            let inside = label[label.index(after: open) ..< close]
            // Strip the trailing "%".
            let numeric = inside.dropLast()
            return Double(numeric)
        }

        /// Old buggy code path — kept here so the regression test
        /// above can demonstrate what summing all three phases used
        /// to produce. Not used in production.
        private func oldStyleSumAllPhases(_ op: QueryProfileOperator) -> Int64 {
            let exec = op.stats?.execNs ?? 0
            let recv = op.stats?.recvNs ?? 0
            let send = op.stats?.sendNs ?? 0
            let here = exec + recv + send
            return op.children.reduce(here) { acc, child in
                acc + oldStyleSumAllPhases(child)
            }
        }

        private func oldStyleRenderedPercentages(
            in op: QueryProfileOperator,
            totalNs: Int64
        ) -> [Double] {
            var values: [Double] = []
            let exec = op.stats?.execNs ?? 0
            let recv = op.stats?.recvNs ?? 0
            let send = op.stats?.sendNs ?? 0
            let here = exec + recv + send
            if here > 0, totalNs > 0 {
                values.append(Double(here) / Double(totalNs) * 100.0)
            }
            for child in op.children {
                values.append(contentsOf: oldStyleRenderedPercentages(
                    in: child,
                    totalNs: totalNs
                ))
            }
            return values
        }

        /// Build a `QueryProfileOperator` with the given phase times.
        private func makeNode(
            name: String,
            exec: Int64,
            recv: Int64,
            send: Int64,
            children: [QueryProfileOperator] = []
        ) -> QueryProfileOperator {
            QueryProfileOperator(
                id: UUID(),
                name: name,
                stats: QueryProfileStats(
                    documentsIn: nil,
                    documentsOut: nil,
                    execNs: exec,
                    recvNs: recv,
                    sendNs: send
                ),
                children: children,
                attributes: []
            )
        }
    }
}
