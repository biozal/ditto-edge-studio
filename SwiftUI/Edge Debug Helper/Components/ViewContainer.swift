//
//  ViewContainer.swift
//  Edge Studio
//
//  Created on today's date.
//

import SwiftUI

// MARK: - View Context Definition
enum ViewContext: Identifiable {
    case home
    case query(subscription: DittoSubscription?)
    case observer(observable: DittoObservable)
    case collection(name: String)
    case empty

    var id: String {
        switch self {
        case .home:
            return "home"
        case .query(let subscription):
            return "query_\(subscription?.id ?? "new")"
        case .observer(let observable):
            return "observer_\(observable.id)"
        case .collection(let name):
            return "collection_\(name)"
        case .empty:
            return "empty"
        }
    }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .query(let subscription):
            return subscription?.name.isEmpty == false ? subscription!.name : "Query"
        case .observer(let observable):
            return observable.name.isEmpty ? "Observer" : observable.name
        case .collection(let name):
            return name
        case .empty:
            return "Store Explorer"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .query:
            return "arrow.trianglehead.2.clockwise"
        case .observer:
            return "eye"
        case .collection:
            return "square.stack.fill"
        case .empty:
            return "cylinder.split.1x2"
        }
    }
}

// MARK: - Unified View Container
struct ViewContainer: View {
    let context: ViewContext
    @Bindable var viewModel: MainStudioView.ViewModel
    let appState: AppState

    var body: some View {
        switch context {
        case .home:
            HomeDetailView(
                syncStatusItems: $viewModel.syncStatusItems,
                isSyncEnabled: $viewModel.isSyncEnabled
            )

        case .query(let subscription):
            VSplitView {
                // Query editor at the top
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isQueryExecuting,
                    onExecuteQuery: {
                        await viewModel.executeQuery(appState: appState)
                    }
                )

                // Results at the bottom
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults
                )
            }
            .onAppear {
                if let subscription = subscription {
                    viewModel.selectedQuery = subscription.query
                }
            }

        case .observer(let observable):
            ObserverDetailView(
                observable: observable,
                events: $viewModel.observableEvents
            )
            .onAppear {
                viewModel.selectedObservable = observable
                Task {
                    await viewModel.loadObservedEvents()
                }
            }

        case .collection(let name):
            VSplitView {
                // Query editor at the top
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isQueryExecuting,
                    onExecuteQuery: {
                        await viewModel.executeQuery(appState: appState)
                    }
                )

                // Results at the bottom
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults
                )
            }
            .onAppear {
                viewModel.selectedQuery = "SELECT * FROM \(name)"
            }

        case .empty:
            DefaultStoreExplorerView()
        }
    }
}

// MARK: - Default Empty View
struct DefaultStoreExplorerView: View {
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Text("Store Explorer")
                        .font(.title2)
                        .bold()

                    Text("Select an item from the sidebar to begin exploring your Ditto store")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Observer Detail View Placeholder
struct ObserverDetailView: View {
    let observable: DittoObservable
    @Binding var events: [DittoObserveEvent]

    var body: some View {
        VStack {
            Text("Observer: \(observable.name)")
                .font(.title2)
            Text("Events: \(events.count)")
            Spacer()
        }
        .padding()
    }
}

