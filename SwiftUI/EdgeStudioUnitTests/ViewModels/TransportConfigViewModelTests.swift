import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Unit tests for the pure, non-Ditto-touching half of
/// `TransportConfigView.ViewModel`: multicast field validation, the
/// validated `multicastConfig` builder, and change detection.
///
/// NOT covered here: the apply/load paths hit a live `Ditto` via
/// `DittoManager.shared` (no injected seam) and require an open database —
/// the decisions they make from the tested state are kept in the pure logic
/// above. See docs/TESTING.md for the coverage policy on SDK-boundary code.
@Suite("TransportConfigViewModel — multicast fields")
@MainActor
struct TransportConfigViewModelTests {
    @Test(.tags(.fast))
    func `Defaults are valid with multicast disabled`() {
        // ARRANGE / ACT
        let viewModel = TransportConfigView.ViewModel()

        // ASSERT — a fresh view model must be immediately applicable: invalid
        // defaults would disable Apply on first open of the settings popover.
        #expect(viewModel.isMulticastEnabled == false)
        #expect(viewModel.isMulticastGroupValid)
        #expect(viewModel.isMulticastPortValid)
        #expect(viewModel.isMulticastInputValid)
        #expect(viewModel.hasChanges == false)
    }

    @Test(.tags(.fast))
    func `Disabled multicast stays valid even with invalid field text`() {
        // ARRANGE
        let viewModel = TransportConfigView.ViewModel()

        // ACT — user types garbage but leaves the transport off
        viewModel.isMulticastEnabled = false
        viewModel.multicastGroupAddress = "not-an-address"
        viewModel.multicastPortText = "0"

        // ASSERT — the enabled flag gates validity, so other transport toggles
        // remain applicable while multicast is off.
        #expect(viewModel.isMulticastInputValid)
    }

    @Test(
        .tags(.fast),
        arguments: ["224.1.2.3", "239.255.255.255"]
    )
    func `Enabled multicast with a valid group and port is valid`(group: String) {
        // ARRANGE
        let viewModel = TransportConfigView.ViewModel()

        // ACT
        viewModel.isMulticastEnabled = true
        viewModel.multicastGroupAddress = group
        viewModel.multicastPortText = "6003"

        // ASSERT
        #expect(viewModel.isMulticastGroupValid)
        #expect(viewModel.isMulticastPortValid)
        #expect(viewModel.isMulticastInputValid)
    }

    @Test(
        .tags(.fast),
        arguments: [
            ("192.168.1.1", "6003"),  // not class-D
            ("224.1.2.3", "0"),       // SDK treats 0 as "any port" — rejected
            ("224.1.2.3", "65536"),   // out of UDP range
            ("224.1.2.3", "abc"),     // non-numeric
            ("224.1.2.3", "")         // empty
        ]
    )
    func `Enabled multicast with invalid input blocks Apply`(
        group: String, port: String
    ) {
        // ARRANGE
        let viewModel = TransportConfigView.ViewModel()

        // ACT
        viewModel.isMulticastEnabled = true
        viewModel.multicastGroupAddress = group
        viewModel.multicastPortText = port

        // ASSERT — Apply stays disabled (`!isMulticastInputValid`) so bad
        // values never reach the SDK's transport validation.
        #expect(viewModel.isMulticastInputValid == false)
    }

    @Test(.tags(.fast))
    func `Multicast config builder trims and normalizes field text`() {
        // ARRANGE
        let viewModel = TransportConfigView.ViewModel()

        // ACT — whitespace-padded group/interface, valid port, blank interface
        viewModel.isMulticastEnabled = true
        viewModel.multicastGroupAddress = "  224.5.6.7  "
        viewModel.multicastPortText = "6003"
        viewModel.multicastInterfaceName = "  en0  "

        // ASSERT
        let config = viewModel.multicastConfig
        #expect(config.isEnabled)
        #expect(config.groupAddress == "224.5.6.7")
        #expect(config.port == 6003)
        #expect(config.interfaceName == "en0")
    }

    @Test(.tags(.fast))
    func `Blank interface name maps to nil for OS-selected interface`() {
        // ARRANGE
        let viewModel = TransportConfigView.ViewModel()

        // ACT
        viewModel.isMulticastEnabled = true
        viewModel.multicastInterfaceName = "   "

        // ASSERT — the SDK treats nil as "let the OS pick"; a blank string
        // would instead be passed as a (failing) interface name.
        #expect(viewModel.multicastConfig.interfaceName == nil)
    }

    @Test(.tags(.fast))
    func `Invalid port text falls back to the default port in the builder`() {
        // ARRANGE
        let viewModel = TransportConfigView.ViewModel()

        // ACT — invalid text can't be applied (Apply is gated), but the
        // builder still yields a struct, never a crash or a zero port.
        viewModel.isMulticastEnabled = true
        viewModel.multicastPortText = "not-a-port"

        // ASSERT
        #expect(viewModel.multicastConfig.port == MulticastConfig.defaultPort)
    }

    @Test(.tags(.fast))
    func `Toggling multicast or editing fields marks the form as changed`() {
        // ARRANGE
        let viewModel = TransportConfigView.ViewModel()
        #expect(viewModel.hasChanges == false)

        // ACT / ASSERT — each multicast field participates in change detection,
        // so Apply enables only when something actually differs.
        viewModel.isMulticastEnabled = true
        #expect(viewModel.hasChanges)

        viewModel.multicastGroupAddress = "224.9.9.9"
        viewModel.multicastPortText = "7001"
        viewModel.multicastInterfaceName = "en0"
        #expect(viewModel.hasChanges)

        // Reverting every field restores the unchanged state.
        viewModel.multicastInterfaceName = ""
        viewModel.multicastPortText = String(MulticastConfig.defaultPort)
        viewModel.multicastGroupAddress = MulticastConfig.defaultGroupAddress
        viewModel.isMulticastEnabled = false
        #expect(viewModel.hasChanges == false)
    }
}
