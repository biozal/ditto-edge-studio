import SwiftUI

/// The Presence Viewer's peer-search box and its results card.
///
/// Rides in the Presence tab bar beside the Peers/Viewer picker so it costs the
/// canvas **no vertical space** — the whole point of the feature is finding one
/// peer in a mesh of 100+ without shrinking the graph you are trying to read.
///
/// ⚠️ This is deliberately a standalone view rather than inline markup in
/// `MainStudioView.syncTabsDetailView()`. That method is a *method on
/// `MainStudioView`*, so anything it reads becomes a dependency of
/// `MainStudioView.body` — the whole `NavigationSplitView`, sidebar included.
/// Reading the query there would re-run all of that on every keystroke (the same
/// trap `SyncLastUpdatedLabel` exists to avoid). Every read of `searchQuery` and
/// `searchMatches` therefore happens in here, in a leaf.
struct PresencePeerSearchField: View {
    @Bindable var viewModel: PresenceViewerSK.ViewModel

    /// Measured so the results card can hang exactly below the box. The card is
    /// an overlay (not a sibling in the layout) so that typing never reflows the
    /// row or the canvas underneath it.
    @State private var fieldHeight: CGFloat = 0

    /// Kept so clearing with the ✕ leaves the caret in the box — the user is
    /// starting a new search, not leaving the field.
    @FocusState private var isFocused: Bool

    var body: some View {
        // The app's search-box idiom: a plain TextField in a tinted capsule with a
        // leading magnifier and a trailing clear button. `.roundedBorder` was wrong
        // here — on macOS it has no clear affordance at all, so a query could only
        // be dismissed by selecting the text or pressing Escape.
        // Matches `SystemMetricsDetailView.searchField`.
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search peers by name or ID…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            #endif
                // Enter jumps straight to the first focusable hit — the "find a
                // peer without touching the mouse" path.
                .onSubmit { viewModel.focusFirstSearchResult() }
                .accessibilityIdentifier("PresencePeerSearchField")
                .accessibilityLabel("Search peers in the mesh")

            if viewModel.searchIsActive {
                Button {
                    viewModel.clearSearch()
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("PresencePeerSearchClearButton")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
        )
        // The picker beside this box refuses to be squeezed
        // (`EqualWidthSegments` never reports less than its widest segment ×
        // count), so on a narrow pane the search box has to be the thing that
        // yields. Negative layout priority makes it the first to give up width.
        //
        // Deliberately no `minWidth`: a minimum is a floor SwiftUI reports back
        // up the tree, so on a pane too narrow for it the row would overflow
        // instead of compressing — trading a cosmetic problem (a short box)
        // for a layout one. The results card is a fixed 320pt anchored to the
        // trailing edge, so it stays readable however narrow the box gets.
        .frame(idealWidth: 240, maxWidth: 260)
        .layoutPriority(-1)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldHeight = $0 }
        .onKeyPress(.escape) {
            viewModel.handleEscape() ? .handled : .ignored
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.searchIsActive {
                resultsCard
                    // `fixedSize` first: without it the card inherits the
                    // box's width proposal and the key column collapses.
                    .fixedSize()
                    .offset(y: fieldHeight + 4)
            }
        }
        // Paint above the canvas below, not behind it.
        .zIndex(1)
    }

    // MARK: - Results card

    /// Drops down over the canvas. Not a `.popover`: on macOS a popover takes key
    /// focus away from the text field, which kills type-ahead — the user would
    /// have to click back into the box after every character.
    private var resultsCard: some View {
        PresencePeerSearchResultsCard(
            query: viewModel.searchQuery,
            matches: viewModel.searchMatches,
            onPick: { viewModel.focusSearchResult($0) }
        )
    }
}
