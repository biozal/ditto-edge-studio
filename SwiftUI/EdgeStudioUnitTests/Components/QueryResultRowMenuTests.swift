import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#endif

@testable import Ditto_Edge_Studio

// MARK: - QueryResultRowMenu Helper Tests
//
// The row context menu itself is a @ViewBuilder (layout, not tested
// here), but two pure free functions in the same file carry real,
// user-facing logic:
//
//   - `extractIdString(fromJSON:)` — turns a result-row JSON document
//     into the clipboard value for "Copy _id". The Table and JSON
//     viewers both depend on this returning a value that round-trips
//     into a `WHERE _id = …` clause, so the string/numeric/composite
//     branches each matter.
//   - `setClipboardString(_:)` — the platform clipboard shim. On macOS
//     we can write then read back through `NSPasteboard.general` to
//     prove the round-trip; that's the only clipboard code path the
//     copy actions funnel through.
//
// These run with no @Environment/@State and no live Ditto, so they're
// fast, deterministic unit tests.

@Suite("QueryResultRowMenu Helpers")
struct QueryResultRowMenuTests {
    // MARK: - extractIdString(fromJSON:)

    @Suite("extractIdString")
    struct ExtractIdStringTests {
        @Test(.tags(.utility, .fast))
        func `String _id is returned raw — the common Ditto case`() {
            // The overwhelmingly common shape: a UUID-ish string _id.
            // It should come back verbatim, no quoting, ready to drop
            // into a WHERE clause the user is composing.
            let json = #"{"_id": "task-001", "title": "Buy milk"}"#
            #expect(extractIdString(fromJSON: json) == "task-001")
        }

        @Test(.tags(.utility, .fast))
        func `Integer _id is stringified to its digits`() {
            // Numeric _ids arrive as NSNumber once JSONSerialization
            // parses them; the helper must render the digits, not a
            // Swift "Optional(...)" or float-y "1.0".
            let json = #"{"_id": 42, "title": "answer"}"#
            #expect(extractIdString(fromJSON: json) == "42")
        }

        @Test(.tags(.utility, .fast))
        func `Composite-key object _id is re-encoded as compact JSON with sorted keys`() {
            // Ditto supports object _ids (composite keys). The helper
            // re-serialises with .sortedKeys and no whitespace so the
            // value is stable and pasteable. Input deliberately lists
            // keys out of alphabetical order to prove sorting happens.
            let json = #"{"_id": {"region": "us", "device": "abc"}, "v": 1}"#

            let result = extractIdString(fromJSON: json)

            // sortedKeys → device before region; compact → no spaces.
            #expect(result == #"{"device":"abc","region":"us"}"#)
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil when the document has no _id`() {
            // A row without _id (e.g. a projection that dropped it)
            // yields nil; callers fall back to copying the whole doc.
            let json = #"{"title": "no id here", "done": true}"#
            #expect(extractIdString(fromJSON: json) == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil for malformed JSON`() {
            // Garbage in → nil out. The copy action then falls back to
            // the raw document rather than crashing.
            #expect(extractIdString(fromJSON: "{not valid json") == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil when the top level is a JSON array, not an object`() {
            // A top-level array has no `_id` key to extract; the guard
            // requires a [String: Any] object.
            #expect(extractIdString(fromJSON: #"["a", "b", "c"]"#) == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Returns nil for an empty string`() {
            // Empty input isn't valid JSON → nil, no crash.
            #expect(extractIdString(fromJSON: "") == nil)
        }

        @Test(.tags(.utility, .fast))
        func `Numeric _id that is a large integer keeps full precision`() {
            // Snowflake-style 64-bit ids must not be mangled into
            // scientific notation or lose trailing digits.
            let json = #"{"_id": 9007199254740993}"#
            #expect(extractIdString(fromJSON: json) == "9007199254740993")
        }
    }

    // MARK: - setClipboardString(_:)

    // `.serialized`: both tests mutate the shared global `NSPasteboard.general`,
    // so they must not run concurrently or one could read back the other's write.
    @Suite("setClipboardString", .serialized)
    struct SetClipboardStringTests {
        #if os(macOS)
        @Test(.tags(.utility, .fast))
        func `Writes the value to the macOS pasteboard so it round-trips`() {
            // The only clipboard path the copy actions use. Write a
            // unique sentinel (so a stale clipboard value can't make
            // this pass falsely) and read it straight back.
            let sentinel = "edge-studio-clipboard-test-\(UUID().uuidString)"

            setClipboardString(sentinel)

            let readBack = NSPasteboard.general.string(forType: .string)
            #expect(readBack == sentinel)
        }

        @Test(.tags(.utility, .fast))
        func `Clears prior contents before writing the new value`() {
            // The macOS impl calls clearContents() first. Writing a
            // second value must fully replace the first, not append.
            setClipboardString("first-\(UUID().uuidString)")
            let second = "second-\(UUID().uuidString)"

            setClipboardString(second)

            #expect(NSPasteboard.general.string(forType: .string) == second)
        }
        #endif
    }
}
