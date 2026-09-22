#if os(iOS)
import XCTest

@MainActor
final class MobileAccessibilityUITests: MobileUITestCase {
    func testDatabaseListAccessibility() throws {
        try app.performAccessibilityAudit()
    }

    func testRegistrationAccessibility() throws {
        try openDatabaseEditor()
        try app.performAccessibilityAudit()
    }
}
#endif
