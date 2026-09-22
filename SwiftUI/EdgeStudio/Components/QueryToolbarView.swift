import SwiftUI

struct QueryToolbarView: View {
    /// Surfaces repository failures. Every mutation below is fire-and-forget
    /// from a `Task`, so without an explicit `catch` a thrown error would be
    /// discarded by the unstructured task and the user would see the row simply
    /// not delete, with no explanation. Matches how `InspectorViews` handles the
    /// same repository calls.
    @Environment(AppState.self) private var appState

    @Binding var collections: [String]
    @Binding var favorites: [DittoQueryHistory]
    @Binding var history: [DittoQueryHistory]
    @Binding var toolbarMode: String
    @Binding var selectedQuery: String
    /// Database this toolbar's session belongs to. Favorite saves forward it
    /// to `FavoritesRepository.saveFavorite(_:databaseId:)`, which refuses
    /// the write if the session has since switched databases.
    var databaseId: String

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Picker("", selection: $toolbarMode) {
                    Label("Collections", systemImage: "square.stack.fill")
                        .labelStyle(.iconOnly)
                        .tag("collections")
                    Label("History", systemImage: "clock")
                        .labelStyle(.iconOnly)
                        .tag("history")
                    Label("Favorites", systemImage: "star")
                        .labelStyle(.iconOnly)
                        .tag("favorites")
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)

            // Content based on toolbarMode
            if toolbarMode == "history" {
                Text("History")
                List(history) { query in
                    VStack(alignment: .leading) {
                        Text(query.query)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.system(.body, design: .monospaced))
                    }
                    .onTapGesture {
                        selectedQuery = query.query
                    }
                    #if os(macOS)
                    .contextMenu {
                        Button("Delete") {
                            Task {
                                do {
                                    try await HistoryRepository.shared.deleteQueryHistory(query.id)
                                } catch {
                                    Log.error("Failed to delete query history: \(error.localizedDescription)")
                                    appState.setError(error)
                                }
                            }
                        }
                        Button("Favorite") {
                            Task {
                                do {
                                    try await FavoritesRepository.shared.saveFavorite(query, databaseId: databaseId)
                                } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                                    // Correctly refused after a database switch —
                                    // don't alert in the NEW session.
                                    Log.info("Favorite save refused: \(error.message)")
                                } catch {
                                    Log.error("Failed to add favorite: \(error.localizedDescription)")
                                    appState.setError(error)
                                }
                            }
                        }
                    }
                    #else
                    .swipeActions(edge: .trailing) {
                            Button(role: .cancel) {
                                Task {
                                    do {
                                        try await FavoritesRepository.shared
                                            .saveFavorite(query, databaseId: databaseId)
                                    } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                                        Log.info("Favorite save refused: \(error.message)")
                                    } catch {
                                        Log.error("Failed to add favorite: \(error.localizedDescription)")
                                        appState.setError(error)
                                    }
                                }
                            } label: {
                                Label("Favorite", systemImage: "star")
                            }

                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await HistoryRepository.shared.deleteQueryHistory(query.id)
                                    } catch {
                                        Log.error("Failed to delete query history: \(error.localizedDescription)")
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
                Button {
                    Task {
                        do {
                            try await HistoryRepository.shared.clearQueryHistory()
                        } catch {
                            Log.error("Failed to clear query history: \(error.localizedDescription)")
                            appState.setError(error)
                        }
                    }
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
            } else if toolbarMode == "favorites" {
                Text("Favorites")
                List(favorites) { query in
                    VStack(alignment: .leading) {
                        Text(query.query)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.system(.body, design: .monospaced))
                    }
                    .onTapGesture {
                        selectedQuery = query.query
                    }
                    #if os(macOS)
                    .contextMenu {
                        Button("Delete") {
                            Task {
                                do {
                                    try await FavoritesRepository.shared.deleteFavorite(query.id)
                                } catch {
                                    Log.error("Failed to delete favorite: \(error.localizedDescription)")
                                    appState.setError(error)
                                }
                            }
                        }
                    }
                    #else
                    .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await FavoritesRepository.shared.deleteFavorite(query.id)
                                    } catch {
                                        Log.error("Failed to delete favorite: \(error.localizedDescription)")
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
            } else {
                Text("Collections")
                List(collections, id: \.self) { collection in
                    Text(collection)
                        .onTapGesture {
                            selectedQuery = "SELECT * FROM \(collection)"
                        }
                    Divider()
                }
            }
            Spacer()
        }
    }
}

#Preview {
    QueryToolbarView(
        collections: .constant([
            "movies",
            "users",
            "products"
        ]),
        favorites: .constant([
            DittoQueryHistory(
                id: "1",
                query: "SELECT * FROM movies",
                createdDate: Date.now.addingTimeInterval(-3600)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "2",
                query: "SELECT * FROM users WHERE age > 21",
                createdDate: Date.now.addingTimeInterval(-7200)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "3",
                query: "SELECT name, price FROM products WHERE inStock = true",
                createdDate: Date.now.addingTimeInterval(-86400)
                    .ISO8601Format()
            )
        ]),
        history: .constant([
            DittoQueryHistory(
                id: "1",
                query: "SELECT * FROM movies",
                createdDate: Date.now.addingTimeInterval(-3600)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "2",
                query: "SELECT * FROM users WHERE age > 21",
                createdDate: Date.now.addingTimeInterval(-7200)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "3",
                query: "SELECT name, price FROM products WHERE inStock = true",
                createdDate: Date.now.addingTimeInterval(-86400)
                    .ISO8601Format()
            )
        ]),
        toolbarMode: .constant("collections"),
        selectedQuery: .constant("SELECT * FROM movies"),
        databaseId: "preview-database"
    )
    // Required: the delete/favorite actions read `appState` from the
    // environment, which traps if nothing provides it.
    .environment(AppState())
}
