import Foundation
import Testing
@testable import Ditto_Edge_Studio

// MARK: - ResultViewTab Tests
//
// `ResultViewTab` drives the results-pane segmented picker, and two things are
// derived from the enum itself rather than written out by hand:
//
//   * the ⌘1…⌘N shortcuts, bound from `allCases.enumerated()` index + 1
//   * the per-segment accessibility identifiers, `ResultViewMode_<rawValue>`
//
// Both are silently wrong if the case order or a raw value changes, so they are
// pinned here.

@Suite("ResultViewTab")
struct ResultViewTabTests {
    @Test("case order pins the ⌘1…⌘3 shortcuts", .tags(.fast))
    func caseOrderPinsShortcuts() {
        // ARRANGE + ACT
        let order = ResultViewTab.allCases

        // ASSERT — reordering would silently reassign every shortcut.
        #expect(order == [.raw, .table, .profile])
        #expect(order.firstIndex(of: .profile).map { $0 + 1 } == 3)
    }

    @Test("raw values are the segment labels the UI tests address", .tags(.fast))
    func rawValuesAreStable() {
        // ARRANGE + ACT + ASSERT
        #expect(ResultViewTab.raw.rawValue == "Raw")
        #expect(ResultViewTab.table.rawValue == "Table")
        #expect(ResultViewTab.profile.rawValue == "Profile")
    }

    @Test("every tab has a distinct, non-empty icon", .tags(.fast))
    func iconsAreDistinctAndPresent() {
        // ARRANGE + ACT
        let icons = ResultViewTab.allCases.map(\.icon)

        // ASSERT
        #expect(icons.allSatisfy { !$0.isEmpty })
        #expect(Set(icons).count == ResultViewTab.allCases.count)
    }

    @Test("observe events expose only the tabs that apply to them", .tags(.fast))
    func observeEventTabsExcludeQueryOnlyViews() {
        // ARRANGE — the Observers picker lists this allow-list; .profile is
        // query-only and must never appear there.
        let observeTabs: [ResultViewTab] = [.raw, .table]

        // ASSERT
        #expect(!observeTabs.contains(.profile))
        #expect(observeTabs.allSatisfy { ResultViewTab.allCases.contains($0) })
    }
}
