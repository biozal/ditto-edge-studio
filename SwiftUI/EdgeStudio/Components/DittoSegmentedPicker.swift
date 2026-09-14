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
        EqualWidthSegments {
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

/// Lays segments out at equal widths, and never reports an ideal width narrower
/// than the widest segment needs.
///
/// The obvious spelling — an `HStack` of segments each carrying
/// `.frame(maxWidth: .infinity)` — divides whatever width it is offered evenly,
/// but its *ideal* width is only the **sum of the segments' natural widths**.
/// Rendered at that ideal, every segment gets `sum / count`, which is narrower
/// than the widest label, so the widest label truncates. That is exactly how the
/// System Metrics namespace filter lost the "Network" segment's text on iPad:
/// nothing in the layout ever asked for the width the labels actually needed.
///
/// Reporting `count × widest` instead makes the control honestly inflexible: a
/// `ViewThatFits` (or any container that respects a child's minimum) can now see
/// that the row does not fit and choose a stacked layout, rather than handing
/// back a width that silently clips text.
private struct EqualWidthSegments: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let natural = subviews.map { $0.sizeThatFits(.unspecified) }
        let widest = natural.map(\.width).max() ?? 0
        let tallest = natural.map(\.height).max() ?? 0
        let ideal = widest * CGFloat(subviews.count)
        // Grow into extra offered width (call sites size these with
        // `.frame(width:)` / `.frame(maxWidth:)` and expect the pill to fill it),
        // but never shrink below `ideal`, whatever is proposed.
        let width: CGFloat = if let proposed = proposal.width, proposed.isFinite {
            max(proposed, ideal)
        } else {
            ideal
        }
        return CGSize(width: width, height: tallest)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let each = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + each * CGFloat(index), y: bounds.minY),
                proposal: ProposedViewSize(width: each, height: bounds.height)
            )
        }
    }
}

#Preview {
    struct PreviewHost: View {
        /// Mirrors the Query Workbench inspector's tabs without pulling a view
        /// model into a reusable component's preview.
        static let inspectorItems = [
            MenuItem(id: 0, name: "History", systemIcon: "clock"),
            MenuItem(id: 1, name: "Favorites", systemIcon: "bookmark"),
            MenuItem(id: 2, name: "JSON", systemIcon: "text.document.fill"),
            MenuItem(id: 3, name: "Metrics", systemIcon: "text.magnifyingglass"),
            MenuItem(id: 4, name: "Help", systemIcon: "questionmark")
        ]

        @State private var namespace = "All"
        @State private var tab = 0
        @State private var inspectorItem = PreviewHost.inspectorItems[0]

        var body: some View {
            VStack(spacing: 24) {
                // The System Metrics namespace filter, squeezed. `EqualWidthSegments`
                // refuses to render narrower than the widest label needs, so each of
                // these is the same width regardless of the frame asked for — which
                // is what stops "Network" being cut off in a narrow iPad pane.
                ForEach([320, 260, 200], id: \.self) { width in
                    DittoSegmentedPicker(
                        options: ["All", "Network", "Store", "Sync", "Other"],
                        selection: $namespace
                    ) { $0 }
                        .frame(maxWidth: CGFloat(width))
                }

                DittoSegmentedPicker(
                    options: [0, 1],
                    selection: $tab,
                    label: { Image(systemName: $0 == 0 ? "person.2" : "point.3.connected.trianglepath.dotted") },
                    verticalPadding: 8
                )
                .frame(maxWidth: 200)

                // The Query Workbench inspector's exact configuration. Kept as a
                // preview because this is the case that regressed: `MenuItem.image`
                // used to bake in a 48pt font, which the native segmented picker
                // clamped and this control does not.
                DittoSegmentedPicker(
                    options: Self.inspectorItems,
                    selection: $inspectorItem,
                    label: { $0.image.font(.system(size: 14)) },
                    verticalPadding: 5
                )
                .frame(width: 300)
            }
            .padding()
        }
    }
    return PreviewHost()
}
