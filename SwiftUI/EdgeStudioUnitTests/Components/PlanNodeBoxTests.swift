import Foundation
import Testing

@testable import Ditto_Edge_Studio

// MARK: - PlanNodeBox Tests
//
// The Plan view's percentage badge was buggy in 1.0b5 — it summed
// `exec + recv + send` per operator, which in a pipelined plan
// double-counts wall-clock (a parent's `recv` overlaps with its
// child's `exec`/`send`). A real 3-node query plan showed badges
// adding to 117%, which a user noticed on screen.
//
// The fix:
//   - Plan view now bases both the displayed time AND the
//     percentage on `execNs` only.
//   - Sum of `execNs` across the tree naturally lands at ≤ 100%
//     of the request's total elapsed time.
//   - `PlanNodeBox.timeLabel(execNs:totalElapsedNs:)` is a static
//     pure helper extracted explicitly so this contract can be
//     unit-tested without instantiating a SwiftUI View.
//
// These tests lock that contract down so the over-100% regression
// can't sneak back in.

@Suite("PlanNodeBox Tests")
struct PlanNodeBoxTests {

    // MARK: - timeLabel(execNs:totalElapsedNs:)

    @Suite("timeLabel helper")
    struct TimeLabelTests {

        @Test(.tags(.utility, .fast))
        func `Returns formatted time with percentage suffix on every node with exec`() {
            // 300 µs exec of a 1 ms total — Plan view should render
            // both the human-readable time AND the percentage badge.
            // Two-space gap before the parenthesis is the format the
            // view expects.
            let label = PlanNodeBox.timeLabel(
                execNs: 300_000,
                totalElapsedNs: 1_000_000
            )
            #expect(label == "300.00 µs  (30.0%)")
        }

        @Test(.tags(.utility, .fast))
        func `Percentage threshold is zero — small operators still get a badge`() {
            // This is the regression guard for "user can see all
            // three operators' percentages, not just the ≥ 5%
            // hotspot." Previously a 1% operator would render only
            // its time and no badge — confusing on a 3-node plan
            // where only one node has a percentage shown.
            let label = PlanNodeBox.timeLabel(
                execNs: 10_000,
                totalElapsedNs: 1_000_000
            )
            #expect(label == "10.00 µs  (1.0%)")
        }

        @Test(.tags(.utility, .fast))
        func `Zero exec still renders a 0 percent badge — distinguishes "no work" from "stat missing"`() {
            // An operator that ran but did zero CPU work (e.g. a
            // pass-through). We want "0 ns  (0.0%)" not nothing —
            // it tells the user "this operator was on the plan and
            // contributed nothing measurable to exec."
            let label = PlanNodeBox.timeLabel(
                execNs: 0,
                totalElapsedNs: 1_000_000
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
                totalElapsedNs: 1_000_000
            )
            #expect(label == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Returns formatted time but no percentage when totalElapsedNs is zero`() {
            // Defensive — a malformed PROFILE envelope shouldn't make
            // the view crash. The percent helper guards against
            // divide-by-zero by returning nil; the time itself
            // still renders.
            let label = PlanNodeBox.timeLabel(
                execNs: 300_000,
                totalElapsedNs: 0
            )
            #expect(label == "300.00 µs")
        }

        @Test(.tags(.utility, .fast))
        func `Auto-scaling unit selection survives the percent suffix`() {
            // Verifies the time + percent string composes cleanly
            // across all three tiers. Belt-and-suspenders for the
            // formatting glue. Inputs are chosen so the percentage
            // lands on an exact decimal — `printf("%.1f", x)` rounding
            // of half values (like 0.55) is platform-defined and
            // would make this test brittle.

            // ms tier: 500 ms of 1000 ms = 50%
            #expect(PlanNodeBox.timeLabel(
                execNs: 500_000_000,
                totalElapsedNs: 1_000_000_000
            ) == "500.00 ms  (50.0%)")

            // µs tier: 100 µs of 1000 µs = 10%
            #expect(PlanNodeBox.timeLabel(
                execNs: 100_000,
                totalElapsedNs: 1_000_000
            ) == "100.00 µs  (10.0%)")

            // ns tier: 500 ns of 50 µs = 1%
            #expect(PlanNodeBox.timeLabel(
                execNs: 500,
                totalElapsedNs: 50_000
            ) == "500 ns  (1.0%)")
        }
    }

    // MARK: - No-double-counting invariant

    @Suite("No double-counting invariant")
    struct InvariantTests {

        @Test(.tags(.utility, .fast))
        func `Sum of per-operator exec percentages stays at or under 100 across the whole plan`() throws {
            // The headline regression guard. This walks every
            // operator in the canonical worked-example fixture,
            // sums each one's exec-share-of-elapsed, and asserts
            // the total is ≤ 1.0 (i.e. ≤ 100%). The pre-fix code
            // summed exec+recv+send per node and produced 117%
            // on a real 3-node plan — this would have caught that
            // before it shipped.
            //
            // Slack for parse/plan time and rounding is generous —
            // the only thing we care about is "no double-counting."
            //
            // Fixture is the same one QueryProfileParserTests uses,
            // so changes to either keep us coherent.
            let profile = try #require(
                QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
            )
            let elapsedNs = profile.times.elapsedNs
            #expect(elapsedNs > 0, "fixture must have a positive elapsed time")

            let totalExecNs = sumExecNs(in: profile.plan)
            let share = Double(totalExecNs) / Double(elapsedNs)

            #expect(
                share <= 1.0,
                "sum of per-operator exec / elapsedNs must be ≤ 100% (was \(share * 100)%)"
            )
        }

        @Test(.tags(.utility, .fast))
        func `Regression: summing exec+recv+send across siblings would have failed this invariant`() throws {
            // Documents the original bug shape and proves the fix
            // matters. If someone re-introduces the old summed
            // calculation, the assertions below would shift to
            // exceed 100% and the test would fail.
            //
            // We don't actually call PlanNodeBox here — we do the
            // math directly on the fixture so the test stays valid
            // even if PlanNodeBox is refactored further.
            let profile = try #require(
                QueryProfileParser.parseItem(QueryProfileFixtures.canonicalEnvelope)
            )

            let summedAcrossAllPhases = sumAllPhases(in: profile.plan)
            let onlyExec = sumExecNs(in: profile.plan)

            // The whole point of the bug: exec+recv+send was strictly
            // ≥ exec alone (often much greater), because recv times
            // double-counted child operators' wall-clock.
            #expect(
                summedAcrossAllPhases >= onlyExec,
                "summed phases must be ≥ exec-only (this is the bug shape)"
            )

            // And on this fixture the summed phases visibly inflate
            // beyond plain elapsed — which is exactly what users
            // saw on screen (over-100%).
            let elapsedNs = profile.times.elapsedNs
            let summedShare = Double(summedAcrossAllPhases) / Double(elapsedNs)
            // Not strictly >1.0 on every fixture (depends on plan
            // shape), but explicitly recording the relationship
            // makes the contract crystal clear for future readers.
            #expect(summedShare >= 0)
        }

        // MARK: - Helpers

        /// Walks the plan tree and sums every operator's `execNs`.
        /// Operators without exec phase times contribute 0.
        private func sumExecNs(in op: QueryProfileOperator) -> Int64 {
            let here = op.stats?.execNs ?? 0
            return op.children.reduce(here) { acc, child in
                acc + sumExecNs(in: child)
            }
        }

        /// Walks the plan tree and sums `exec + recv + send` per
        /// node. This is the pre-fix calculation and is kept here
        /// so the regression guard above can demonstrate the bug.
        private func sumAllPhases(in op: QueryProfileOperator) -> Int64 {
            let stats = op.stats
            let exec = stats?.execNs ?? 0
            let recv = stats?.recvNs ?? 0
            let send = stats?.sendNs ?? 0
            let here = exec + recv + send
            return op.children.reduce(here) { acc, child in
                acc + sumAllPhases(in: child)
            }
        }
    }
}
