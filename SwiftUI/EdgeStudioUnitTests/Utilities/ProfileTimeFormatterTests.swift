import Foundation
import Testing

@testable import Ditto_Edge_Studio

// MARK: - ProfileTimeFormatter Tests
//
// The Profile Plan view depends on this formatter to render
// per-operator times AND the percentage badge. The badge in
// particular is load-bearing — users glance at it to decide which
// operator is the bottleneck — so the formatting and percentage
// math need locked-down coverage.
//
// Two surfaces are tested here:
//   1. `format(ns:)` — three-tier ms/µs/ns auto-scale
//   2. `percentOfTotal(ns:totalNs:threshold:)` — the badge math, with
//      explicit edge cases (zero total, nil ns, threshold gate)
//
// PlanNodeBox's static `timeLabel(execNs:totalElapsedNs:)` helper
// has its own test file — that file covers the integration of
// these two formatters as they appear in the Plan view.

@Suite("ProfileTimeFormatter Tests")
struct ProfileTimeFormatterTests {
    // MARK: - format(ns:)

    @Suite("format(ns:)")
    struct FormatTests {
        @Test(.tags(.utility, .fast))
        func `Milliseconds tier renders with two decimals and ms suffix`() {
            #expect(ProfileTimeFormatter.format(ns: 432_430_000) == "432.43 ms")
            #expect(ProfileTimeFormatter.format(ns: 1_000_000) == "1.00 ms")
            #expect(ProfileTimeFormatter.format(ns: 12_500_000) == "12.50 ms")
        }

        @Test(.tags(.utility, .fast))
        func `Microseconds tier renders with two decimals and us suffix`() {
            #expect(ProfileTimeFormatter.format(ns: 55_560) == "55.56 µs")
            #expect(ProfileTimeFormatter.format(ns: 1_000) == "1.00 µs")
            #expect(ProfileTimeFormatter.format(ns: 999_999) == "1000.00 µs")
        }

        @Test(.tags(.utility, .fast))
        func `Nanosecond tier renders the integer ns value`() {
            #expect(ProfileTimeFormatter.format(ns: 209) == "209 ns")
            #expect(ProfileTimeFormatter.format(ns: 1) == "1 ns")
            #expect(ProfileTimeFormatter.format(ns: 999) == "999 ns")
        }

        @Test(.tags(.utility, .fast))
        func `Zero renders as zero ns not zero ms`() {
            #expect(ProfileTimeFormatter.format(ns: 0) == "0 ns")
        }

        @Test(.tags(.utility, .fast))
        func `Negative values keep the minus sign and pick the right unit by magnitude`() {
            // Magnitude (not signed value) determines the unit so a
            // small negative doesn't get promoted to ms.
            #expect(ProfileTimeFormatter.format(ns: -209) == "-209 ns")
            #expect(ProfileTimeFormatter.format(ns: -55_560) == "-55.56 µs")
            #expect(ProfileTimeFormatter.format(ns: -432_430_000) == "-432.43 ms")
        }

        @Test(.tags(.utility, .fast))
        func `Optional overload returns em dash for nil`() {
            // The em dash visually distinguishes "Ditto didn't report
            // this stat" from "the stat is zero".
            let nilValue: Int64? = nil
            #expect(ProfileTimeFormatter.format(ns: nilValue) == "—")
            #expect(ProfileTimeFormatter.format(ns: Int64?.some(0)) == "0 ns")
        }
    }

    // MARK: - percentOfTotal(...)

    @Suite("percentOfTotal")
    struct PercentTests {
        @Test(.tags(.utility, .fast))
        func `Returns formatted percent for typical share above default threshold`() {
            // 300 µs of a 1000 µs total = 30%. Default threshold is
            // 5%, so this should clear it.
            let result = ProfileTimeFormatter.percentOfTotal(
                ns: 300_000,
                totalNs: 1_000_000
            )
            #expect(result == "30.0%")
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil when share is below default 5 percent threshold`() {
            // 49 µs of a 1000 µs total = 4.9% < 5% default → hidden.
            let result = ProfileTimeFormatter.percentOfTotal(
                ns: 49_000,
                totalNs: 1_000_000
            )
            #expect(result == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Returns badge for any non zero share when threshold is zero`() {
            // PlanNodeBox passes threshold: 0 so even small operators
            // get a percentage on screen — exec-only times are much
            // smaller than the old summed total, so the "noise floor"
            // semantics no longer apply.
            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 1_000,
                totalNs: 1_000_000,
                threshold: 0
            ) == "0.1%")

            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 5_000,
                totalNs: 1_000_000,
                threshold: 0
            ) == "0.5%")

            // 0 ns still produces "0.0%" with threshold 0 — that's
            // an honest report ("operator did no exec work"), not a
            // noise hide.
            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 0,
                totalNs: 1_000_000,
                threshold: 0
            ) == "0.0%")
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil when totalNs is zero to avoid division by zero`() {
            // Defensive — Ditto in theory always reports elapsedNs > 0
            // for a completed PROFILE, but the view shouldn't crash
            // if a malformed envelope sneaks through.
            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 100,
                totalNs: 0
            ) == nil)

            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 100,
                totalNs: -1
            ) == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil when ns is nil regardless of threshold`() {
            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: nil,
                totalNs: 1_000_000
            ) == nil)

            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: nil,
                totalNs: 1_000_000,
                threshold: 0
            ) == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Boundary cases produce expected percentages`() {
            // Exact 100% — operator's exec time equals total elapsed.
            // Should still render (caller can decide).
            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 1_000_000,
                totalNs: 1_000_000
            ) == "100.0%")

            // 99.9% — verifies one-decimal rounding doesn't snap to 100.
            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 999_000,
                totalNs: 1_000_000
            ) == "99.9%")

            // Exact 5% — should render under the default threshold
            // (the gate is `share < threshold`, strict).
            #expect(ProfileTimeFormatter.percentOfTotal(
                ns: 50_000,
                totalNs: 1_000_000
            ) == "5.0%")
        }
    }
}
