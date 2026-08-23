import Foundation
import Testing

@testable import Ditto_Edge_Studio

// MARK: - ProfileViewer Helper Tests
//
// The Profile cards (ProfileStatsBadges, ProfileSummaryStrip, …) are
// SwiftUI layout and aren't unit-tested here. But the document-count
// formatter they all share — `ProfileFormat.documents(_:)` — is a pure
// value-in/value-out helper that renders the `in` / `out` / RESULT
// COUNT numbers users read off the profile UI.
//
// It wraps a NumberFormatter configured for `.decimal` with grouping
// separators, so its output is LOCALE-DEPENDENT (the thousands
// separator is "," in en_US, "." in de_DE, a thin space in fr_FR, …).
// CI machines don't guarantee a locale, so these tests assert on the
// locale-INVARIANT properties of the result — digit sequence, absence
// of a decimal point, monotonic grouping behaviour — rather than the
// exact separator glyph. That keeps them deterministic everywhere
// while still pinning the meaningful contract.

@Suite("ProfileViewer Helpers")
struct ProfileViewerHelpersTests {

    // MARK: - ProfileFormat.documents(_:)

    @Suite("ProfileFormat.documents")
    struct DocumentsTests {

        /// Strips any non-digit grouping separators so we can compare
        /// the significant digits independent of the host locale.
        private func digitsOnly(_ s: String) -> String {
            s.filter(\.isNumber)
        }

        @Test(.tags(.utility, .fast))
        func `Small counts render with no grouping separator`() {
            // Under 1000 there's nothing to group — the output is just
            // the digits, in every locale.
            #expect(ProfileFormat.documents(0) == "0")
            #expect(ProfileFormat.documents(7) == "7")
            #expect(ProfileFormat.documents(999) == "999")
        }

        @Test(.tags(.utility, .fast))
        func `Thousands are grouped with exactly one separator`() {
            // 1000 picks up a single grouping separator. We don't care
            // WHICH glyph (locale-defined), only that the four
            // significant digits survive and one non-digit was
            // inserted.
            let result = ProfileFormat.documents(1000)

            #expect(digitsOnly(result) == "1000")
            // One grouping separator → exactly one non-digit character.
            #expect(result.filter { !$0.isNumber }.count == 1)
        }

        @Test(.tags(.utility, .fast))
        func `Large counts preserve every significant digit`() {
            // The value from the bug screenshot's `out: 23,539` badge.
            // Whatever the separator, the digits must be intact and in
            // order — a NumberFormatter misconfigured for currency or
            // scientific notation would corrupt this.
            let result = ProfileFormat.documents(23_539)

            #expect(digitsOnly(result) == "23539")
        }

        @Test(.tags(.utility, .fast))
        func `Result has no fractional part — counts are whole numbers`() {
            // Document counts are integers; the formatter must not emit
            // a fractional part like "1.00". Guards against someone
            // setting minimumFractionDigits on the shared formatter.
            //
            // We can't simply forbid "." or "," because either can be
            // the LOCALE's grouping separator. Instead we assert there
            // are no MORE digits than the integer has — a fractional
            // part would add trailing zero digits.
            for value in [0, 5, 1000, 23_539, 1_000_000] {
                let result = ProfileFormat.documents(value)
                #expect(
                    digitsOnly(result) == String(value),
                    "\(value) → \(result): formatted digits must match the integer exactly (no fractional zeros)"
                )
            }
        }

        @Test(.tags(.utility, .fast))
        func `Million-scale count keeps all seven digits`() {
            // Two grouping breaks at 1,000,000. Digit sequence must be
            // exactly seven characters "1000000".
            let result = ProfileFormat.documents(1_000_000)
            #expect(digitsOnly(result) == "1000000")
        }

        @Test(.tags(.utility, .fast))
        func `Negative counts are not expected but still format without crashing`() {
            // Defensive: document counts should never be negative, but
            // the helper takes a plain Int and must not trap on one.
            // We only assert the digits round-trip; the sign glyph is
            // locale-formatted.
            let result = ProfileFormat.documents(-5)
            #expect(digitsOnly(result) == "5")
        }
    }
}
