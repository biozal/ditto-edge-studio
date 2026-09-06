import SwiftUI

/// A segmented picker whose selected segment is Ditto yellow with black content.
///
/// ## Why this exists rather than `.pickerStyle(.segmented)`
///
/// The stock segmented style paints its selection with the system accent and
/// offers no supported hook to change it: on iOS it is a `UISegmentedControl`
/// underneath, whose `selectedSegmentTintColor` can only be reached through the
/// global `UIAppearance` proxy (which would restyle every segmented control in
/// the app, and does nothing on macOS, where the control is an
/// `NSSegmentedControl`). A small custom control is the only way to get the
/// brand colour on both platforms without a global side effect.
///
/// Android reached the same conclusion for the same reason — see
/// `SegmentedButtonDefaults.colors(activeContainerColor = SulfurYellow,
/// activeContentColor = Color.Black)` in `DiskUsageScreen.kt`. The selected
/// colours here match it deliberately: the same control should look the same on
/// every platform.
///
/// ## Dark mode only
///
/// The brand yellow is applied **only in dark mode**, where it reads as a bright
/// accent against a dark chrome — the same role it plays on Android, whose UI is
/// dark. In light mode a yellow fill with black text is heavy and muddy next to
/// the surrounding system controls, so the selection falls back to the accent
/// colour the stock segmented picker would have used. Light mode therefore looks
/// as it always did; only dark mode is branded.
///
/// `label` is a `@ViewBuilder`, so a segment can be text, an SF Symbol, or a
/// `Label`. Symbols inherit the selected foreground style the same way text
/// does, which is what lets the icon-only navigation pickers use this too.
struct DittoSegmentedPicker<Value: Hashable, SegmentLabel: View>: View {
    let options: [Value]
    @Binding var selection: Value
    @ViewBuilder let label: (Value) -> SegmentLabel

    /// Extra vertical padding per segment. The icon-only navigation pickers
    /// used `.controlSize(.extraLarge)`; this is the equivalent knob.
    var verticalPadding: CGFloat = 5

    @Environment(\.colorScheme) private var colorScheme

    /// Fill behind the selected segment.
    private var selectedFill: Color {
        colorScheme == .dark ? Color.dittoYellow : Color.accentColor
    }

    /// Content colour on the selected segment, paired with `selectedFill`.
    private var selectedForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                segment(option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.14))
        )
        .accessibilityIdentifier("DittoSegmentedPicker")
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            label(option)
                .lineLimit(1)
                .foregroundStyle(isSelected ? selectedForeground : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? selectedFill : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension DittoSegmentedPicker where SegmentLabel == Text {
    /// Text-titled segments — the common case.
    init(
        options: [Value],
        selection: Binding<Value>,
        verticalPadding: CGFloat = 5,
        title: @escaping (Value) -> String
    ) {
        self.init(
            options: options,
            selection: selection,
            label: { Text(title($0)).font(.caption.weight(.medium)) },
            verticalPadding: verticalPadding
        )
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var namespace = "All"
        @State private var tab = 0

        var body: some View {
            VStack(spacing: 24) {
                DittoSegmentedPicker(
                    options: ["All", "Network", "Store", "Sync", "Other"],
                    selection: $namespace
                ) { $0 }
                    .frame(maxWidth: 320)

                DittoSegmentedPicker(
                    options: [0, 1],
                    selection: $tab,
                    label: { Image(systemName: $0 == 0 ? "person.2" : "point.3.connected.trianglepath.dotted") },
                    verticalPadding: 8
                )
                .frame(maxWidth: 200)
            }
            .padding()
        }
    }
    return PreviewHost()
}
