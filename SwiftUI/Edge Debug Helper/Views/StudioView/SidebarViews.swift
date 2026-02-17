import SwiftUI

extension MainStudioView {
    func subscriptionSidebarView() -> some View {
        VStack(alignment: .leading) {
            headerView(title: "Subscriptions")
            if viewModel.isLoading {
                Spacer()
                AnyView(ProgressView("Loading Subscriptions...")
                    .progressViewStyle(.circular))
                Spacer()
            } else if viewModel.subscriptions.isEmpty {
                Spacer()
                AnyView(ContentUnavailableView(
                    "No Subscriptions",
                    systemImage:
                    "exclamationmark.triangle.fill",
                    description: Text("No apps have been added yet. Click the plus button in the bottom left corner to add your first subscription.")
                ))
                Spacer()
            } else {
                SubscriptionList(
                    subscriptions: $viewModel.subscriptions,
                    onEdit: viewModel.showSubscriptionEditor,
                    onDelete: viewModel.deleteSubscription,
                    appState: appState
                )
            }
        }
    }

    private func collectionsHeaderView() -> some View {
        HStack {
            Spacer()

            Text("Ditto Collections")
                .padding(.top, 4)

            Spacer()

            Button {
                Task {
                    await viewModel.refreshCollectionCounts()
                }
            } label: {
                if viewModel.isRefreshingCollections {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    FontAwesomeText(icon: NavigationIcon.refresh, size: 14)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshingCollections)
            .help("Refresh document counts")
            .padding(.trailing, 8)
            .padding(.top, 4)
        }
    }

    func collectionsSidebarView() -> some View {
        VStack(alignment: .leading) {
            collectionsHeaderView()
            if viewModel.isLoading {
                Spacer()
                AnyView(ProgressView("Loading Collections...")
                    .progressViewStyle(.circular))
                Spacer()
            } else if viewModel.collections.isEmpty {
                Spacer()
                AnyView(ContentUnavailableView(
                    "No Collections",
                    systemImage:
                    "exclamationmark.triangle.fill",
                    description: Text("No Collections found. Add some data or use the Import button to load data into the database.")
                ))
                Spacer()
            } else {
                List(viewModel.collections, id: \._id) { collection in
                    HStack {
                        Text(collection.name)

                        Spacer()

                        // Badge showing document count (like Mail.app)
                        if let count = collection.documentCount {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(10)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedQuery =
                            "SELECT * FROM \(collection.name)"
                    }
                    Divider()
                }
                Spacer()
            }
        }
    }

    func observeSidebarView() -> some View {
        VStack(alignment: .leading) {
            headerView(title: "Observers")
            if viewModel.observerables.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Observers",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("No observers have been added yet. Click the plus button to add your first observers.")
                )
            } else {
                List(viewModel.observerables) { observer in
                    observerCard(observer: observer)
                        .onTapGesture {
                            viewModel.selectedObservable = observer
                            Task {
                                await viewModel.loadObservedEvents()
                            }
                        }
                    #if os(macOS)
                        .contextMenu {
                            if observer.storeObserver == nil {
                                Button {
                                    Task {
                                        do {
                                            try await viewModel.registerStoreObserver(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                } label: {
                                    Label(
                                        "Activate",
                                        systemImage: "play.circle"
                                    )
                                    .labelStyle(.titleAndIcon)
                                }
                            } else {
                                Button {
                                    Task {
                                        do {
                                            try await viewModel.removeStoreObserver(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                } label: {
                                    Label(
                                        "Stop",
                                        systemImage: "stop.circle"
                                    )
                                    .labelStyle(.titleAndIcon)
                                }
                            }
                            Button {
                                Task {
                                    do {
                                        try await viewModel.deleteObservable(observer)
                                    } catch {
                                        appState.setError(error)
                                    }
                                }
                            } label: {
                                Label(
                                    "Delete",
                                    systemImage: "trash"
                                )
                                .labelStyle(.titleAndIcon)
                            }
                        }
                    #else
                        .swipeActions(edge: .trailing) {
                            if observer.storeObserver == nil {
                                Button {
                                    Task {
                                        do {
                                            try await viewModel.registerStoreObserver(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                } label: {
                                    Label("Activate", systemImage: "play.circle")
                                }
                            } else {
                                Button {
                                    Task {
                                        do {
                                            try await viewModel.removeStoreObserver(observer)
                                        } catch {
                                            appState.setError(error)
                                        }
                                    }
                                } label: {
                                    Label("Stop", systemImage: "stop.circle")
                                }
                            }
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await viewModel.deleteObservable(observer)
                                    } catch {
                                        appState.setError(error)
                                    }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    #endif
                    Divider()
                }
            }
            Spacer()
        }
    }

    private func observerCard(observer: DittoObservable) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(observer.storeObserver == nil ? Color.gray.opacity(0.15) : Color.green.opacity(0.15))
                .shadow(radius: 1)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(observer.name)
                        .font(.headline)
                        .bold()
                }
                Spacer()
                if observer.storeObserver == nil {
                    Text("Idle")
                        .font(.subheadline)
                        .padding(.trailing, 4)
                } else {
                    Text("Active")
                        .font(.subheadline)
                        .bold()
                        .padding(.trailing, 4)
                }
            }
            .padding()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    func headerView(title: String) -> some View {
        HStack {
            Spacer()
            Text(title)
                .padding(.top, 4)
            Spacer()
        }
    }
}
