//
//  QueryToolbarView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/5/25.
//

import SwiftUI

struct QueryToolbarView: View {
    @Binding var collections: [String]
    @Binding var favorites: [DittoQueryHistory]
    @Binding var history: [DittoQueryHistory]
    @Binding var toolbarMode: String
    @Binding var selectedQuery: String
    @Binding var isMongoConnected: Bool
    @Binding var mongoCollections: [String]

    var body: some View {
        VStack{
            HStack{
               Spacer()
                Picker("", selection: $toolbarMode){
                    Label("Collections", systemImage: "square.stack.fill")
                        .labelStyle(.iconOnly)
                        .tag("collections")
                    Label("History", systemImage: "clock")
                        .labelStyle(.iconOnly)
                        .tag("history")
                    Label("Favorites", systemImage: "star")
                        .labelStyle(.iconOnly)
                        .tag("favorites")
                    if (isMongoConnected) {
                        Label("MongoDB", systemImage: "leaf")
                            .labelStyle(.iconOnly)
                            .tag("mongo")
                    }
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
                        Button ("Delete"){
                            Task {
                                    try await DittoManager.shared.deleteQueryHistory(query.id)
                                }
                            }
                        Button ("Favorite"){
                            Task {
                                try await DittoManager.shared.saveFavorite(query)
                            }
                        }
                    }
                    #else
                    .swipeActions(edge: .trailing) {
                        Button(role: .cancel) {
                            Task {
                                try await DittoManager.shared
                                    .saveFavorite(query)
                            }
                        } label: {
                            Label("Favorite", systemImage: "star")
                        }
                        
                        Button(role: .destructive) {
                            Task {
                                try await DittoManager.shared.deleteQueryHistory(query.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    #endif
                    Divider()
                }
                Button  {
                    Task {
                        try await DittoManager.shared.clearQueryHistory()
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
                        Button ("Delete"){
                            Task {
                                try await DittoManager.shared.deleteFavorite(query.id)
                            }
                        }
                    }
#else
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                try await DittoManager.shared.deleteFavorite(query.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
#endif
                    Divider()
                }
            } else if toolbarMode == "collections" {
                Text("Ditto Collections")
                List(collections, id: \.self) { collection in
                    Text(collection)
                        .onTapGesture {
                            selectedQuery = "SELECT * FROM \(collection)"
                        }
                    Divider()
                }
            } else {
                Text("MongoDB Collections")
                if (mongoCollections.isEmpty) {
                    
                } else {
                    List(mongoCollections, id: \.self){ collection in
                        Text(collection)
                            .onTapGesture {
                                
                            }
                        Divider()
                    }
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
        favorites:  .constant([
            DittoQueryHistory(
                id: "1",
                query: "SELECT * FROM movies",
                createdDate: Date().addingTimeInterval(-3600)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "2",
                query: "SELECT * FROM users WHERE age > 21",
                createdDate: Date().addingTimeInterval(-7200)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "3",
                query: "SELECT name, price FROM products WHERE inStock = true",
                createdDate: Date().addingTimeInterval(-86400)
                    .ISO8601Format()
            )
        ]),
        history: .constant([
            DittoQueryHistory(
                id: "1",
                query: "SELECT * FROM movies",
                createdDate: Date().addingTimeInterval(-3600)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "2",
                query: "SELECT * FROM users WHERE age > 21",
                createdDate: Date().addingTimeInterval(-7200)
                    .ISO8601Format()
            ),
            DittoQueryHistory(
                id: "3",
                query: "SELECT name, price FROM products WHERE inStock = true",
                createdDate: Date().addingTimeInterval(-86400)
                    .ISO8601Format()
            )
        ]),
        toolbarMode: .constant("collections"),
        selectedQuery: .constant("SELECT * FROM movies"),
        isMongoConnected: .constant(true),
        mongoCollections: .constant([
            "movies",
            "users",
            "products"
        ]),
    )
}

