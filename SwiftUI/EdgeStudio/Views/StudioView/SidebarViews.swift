import SwiftUI

extension MainStudioView {
    // MARK: - iPad helpers

    /// True when running on iPad (iOS regular horizontal size class).
    /// Internal access so MainStudioView.swift can also use it.
    var isIPadRegular: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    /// Row label font — smaller on iPad to prevent wrapping in the narrow sidebar.
    private var sidebarItemFont: Font {
        isIPadRegular ? .footnote : .body
    }

    // MARK: - Unified Sidebar

    func unifiedSidebarView() -> some View {
        List {
            // ── Top Navigation Items ─────────────────────────────────────
            // Like Apple Music's Search / Home / New / Radio rows — these
            // are the primary way to switch the detail view on the right.
            // Metrics destinations are filtered into `availableDestinations`
            // by `metricsEnabled`, so a single ForEach covers both cases.
            Section {
                ForEach(availableDestinations) { destination in
                    let isSelected = viewModel.selectedSidebarDestination == destination
                    Button {
                        viewModel.selectedSidebarDestination = destination
                    } label: {
                        Label {
                            Text(destination.displayName)
                                .foregroundStyle(isSelected ? Color.black : .primary)
                                .fontWeight(isSelected ? .semibold : .regular)
                        } icon: {
                            Image(systemName: destination.systemIcon)
                                .foregroundStyle(isSelected ? Color.black : .secondary)
                        }
                        #if os(iOS)
                        .font(.subheadline)
                        #endif
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.dittoYellow : Color.clear)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                    )
                }
            }

            // ── Subscriptions Content Section ────────────────────────────
            Section {
                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.subObsVM.subscriptions.isEmpty {
                    ContentUnavailableView {
                        Label("No Subscriptions", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    } description: {
                        Text("Subscriptions sync data from the server in real time.")
                    } actions: {
                        Button {
                            presentNewSubscriptionEditor()
                        } label: {
                            Label("Add Subscription", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.dittoYellow)
                        .foregroundStyle(Color.black)
                        .accessibilityIdentifier("EmptySubscriptionsAddButton")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    subscriptionTreeRows()
                }
            } header: {
                HStack(spacing: 6) {
                    Text("SUBSCRIPTIONS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        activeSheet = .subscriptionQRDisplay
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.subObsVM.subscriptions.isEmpty)
                }
            }

            // ── Collections Content Section ──────────────────────────────
            Section {
                if viewModel.collections.isEmpty {
                    ContentUnavailableView {
                        Label("No Collections", systemImage: "tray")
                    } description: {
                        Text("Collections appear once data is synced or imported into this database.")
                    } actions: {
                        Button {
                            viewModel.selectedSidebarDestination = .query
                        } label: {
                            Label("Run a Query", systemImage: "macpro.gen2")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.dittoYellow)
                        .foregroundStyle(Color.black)
                        .accessibilityIdentifier("EmptyCollectionsQueryButton")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    collectionTreeRows()
                }
            } header: {
                HStack(spacing: 6) {
                    Text("COLLECTIONS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await viewModel.refreshCollectionCounts() }
                    } label: {
                        if viewModel.isRefreshingCollections {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshingCollections)
                }
            }

            // ── Observers Content Section ────────────────────────────────
            Section {
                if viewModel.subObsVM.observerables.isEmpty {
                    ContentUnavailableView {
                        Label("No Observers", systemImage: "eye")
                    } description: {
                        Text("Observers stream real-time changes for a saved query.")
                    } actions: {
                        Button {
                            presentNewObserverEditor()
                        } label: {
                            Label("Add Observer", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.dittoYellow)
                        .foregroundStyle(Color.black)
                        .accessibilityIdentifier("EmptyObserversAddButton")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    observerTreeRows()
                }
            } header: {
                Text("OBSERVERS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        #endif
    }

    // MARK: - Subscription Tree

    private func subscriptionTreeRows() -> some View {
        ForEach(viewModel.subObsVM.subscriptions) { sub in
            DisclosureGroup(isExpanded: expandedSubscriptionBinding(for: sub)) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                    Text(sub.query.isEmpty ? "No query" : sub.query)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 4)
            } label: {
                Button {
                    expandedSubscriptionIds.formSymmetricDifference([sub.id])
                    viewModel.selectedSidebarDestination = .subscriptions
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName:
                            "arrow.trianglehead.2.clockwise.rotate.90"
                        )
                        .foregroundStyle(.secondary)
                        Text(sub.name)
                            .font(sidebarItemFont)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .contextMenu {
                Button("Edit") { presentSubscriptionEditor(sub) }
                Divider()
                Button("Delete", role: .destructive) {
                    Task {
                        do { try await viewModel.subObsVM.deleteSubscription(sub) } catch
                        { appState.setError(error) }
                    }
                }
            }
        }
    }

    // MARK: - Collection Tree

    private func collectionTreeRows() -> some View {
        ForEach(viewModel.collections, id: \._id) { collection in
            DisclosureGroup(isExpanded: expandedBinding(for: collection)) {
                ForEach(collection.indexes) { index in
                    DisclosureGroup {
                        ForEach(index.fields, id: \.self) { field in
                            HStack(spacing: 6) {
                                Image(systemName: "capsule.fill")
                                    .foregroundStyle(.tertiary)
                                Text(field.strippingBackticks)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "i.circle")
                                .foregroundStyle(.secondary)
                            Text(index.displayName)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            } label: {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "book.pages")
                            .foregroundStyle(.secondary)
                        Text(collection.name)
                            .font(sidebarItemFont)
                    }
                    Spacer()
                    if let count = collection.documentCount {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(
                                colorScheme == .dark
                                    ? .black : Color.dittoYellow
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                colorScheme == .dark
                                    ? Color.dittoYellow : Color.black
                            )
                            .cornerRadius(10)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.queryVM.selectedQuery = "SELECT * FROM \(collection.name)"
                    viewModel.selectedSidebarDestination = .query
                }
            }
            .contextMenu {
                Button {
                    viewModel.queryVM.selectedQuery = "SELECT * FROM \(collection.name)"
                    viewModel.selectedSidebarDestination = .query
                } label: {
                    Label("SELECT * FROM \(collection.name)", systemImage: "arrow.right.doc.on.clipboard")
                }
            }
        }
    }

    // MARK: - Observer Tree

    private func observerTreeRows() -> some View {
        ForEach(viewModel.subObsVM.observerables) { observer in
            DisclosureGroup(isExpanded: expandedObserverBinding(for: observer)) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.tertiary)
                    Text(observer.query.isEmpty ? "No query" : observer.query)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 4)
            } label: {
                Button {
                    expandedObserverIds.formSymmetricDifference([observer.id])
                    viewModel.subObsVM.selectedObservable = observer
                    viewModel.selectedSidebarDestination = .observers
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                        Text(observer.name)
                            .font(sidebarItemFont)
                        Spacer()
                        if observer.storeObserver != nil {
                            Text("Active")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            #if os(macOS)
            .contextMenu {
                if observer.storeObserver == nil {
                    Button {
                        Task {
                            do {
                                try await viewModel.subObsVM.registerStoreObserver(observer)
                                viewModel.subObsVM.selectedObservable = observer
                                viewModel.selectedSidebarDestination = .observers
                            } catch { appState.setError(error) }
                        }
                    } label: {
                        Label("Activate", systemImage: "play.circle")
                            .labelStyle(.titleAndIcon)
                    }
                } else {
                    Button {
                        Task {
                            do {
                                try await viewModel.subObsVM.removeStoreObserver(
                                    observer
                                )
                            } catch { appState.setError(error) }
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                            .labelStyle(.titleAndIcon)
                    }
                }
                Button {
                    Task {
                        do {
                            try await viewModel.subObsVM.deleteObservable(observer)
                        } catch { appState.setError(error) }
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
            }
            #else
            .swipeActions(edge: .trailing) {
                    if observer.storeObserver == nil {
                        Button {
                            Task {
                                do {
                                    try await viewModel.subObsVM.registerStoreObserver(observer)
                                    viewModel.subObsVM.selectedObservable = observer
                                    viewModel.selectedSidebarDestination = .observers
                                } catch { appState.setError(error) }
                            }
                        } label: {
                            Label("Activate", systemImage: "play.circle")
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    try await viewModel.subObsVM.removeStoreObserver(
                                        observer
                                    )
                                } catch { appState.setError(error) }
                            }
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button(role: .destructive) {
                        Task {
                            do {
                                try await viewModel.subObsVM.deleteObservable(observer)
                            } catch { appState.setError(error) }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            #endif
        }
    }
}

// MARK: - ObserverCard (kept for potential reuse)

struct ObserverCard: View {
    let observer: DittoObservable
    @Environment(\.colorScheme) var colorScheme

    private var isActive: Bool {
        observer.storeObserver != nil
    }

    private var gradientColors: [Color] {
        if isActive {
            return colorScheme == .dark
                ? [
                    Color(red: 0.08, green: 0.28, blue: 0.12),
                    Color(red: 0.04, green: 0.16, blue: 0.08)
                ]
                : [
                    Color(red: 0.82, green: 0.95, blue: 0.82),
                    Color(red: 0.70, green: 0.88, blue: 0.70)
                ]
        } else {
            return colorScheme == .dark
                ? [Color.Ditto.trafficBlack, Color.Ditto.jetBlack]
                : [Color.Ditto.trafficWhite, Color.Ditto.papyrusWhite]
        }
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.40 : 0.15
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(observer.name)
                    .font(.headline)
                    .bold()
                    .foregroundColor(.primary)
            }
            Spacer()
            if isActive {
                Text("Active")
                    .font(.subheadline)
                    .bold()
                    .padding(.trailing, 4)
            } else {
                Text("Idle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: Color.black.opacity(shadowOpacity),
                    radius: 6,
                    x: 0,
                    y: 3
                )
        )
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}
