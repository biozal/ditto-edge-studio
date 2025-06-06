//
//  QueryToolbarView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/5/25.
//

import SwiftUI

struct QueryToolbarView: View {
    @Binding var collections: [String]
    var queries: [DittoQueryHistory]
    @Binding var favorites: [String:String]
    @Binding var toolbarMode: String
    @Binding var selectedQuery: String
    
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
                List(queries) { query in
                    VStack(alignment: .leading) {
                        Text(query.query)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.system(.body, design: .monospaced))
                    }
                    .onTapGesture {
                        selectedQuery = query.query
                    }
                }
            } else if toolbarMode == "favorites" {
                Text("Favorites")
            } else {
                Text("Collections")
                List(collections, id: \.self) { collection in
                    Text(collection)
                        .onTapGesture {
                            selectedQuery = "SELECT * FROM \(collection)"
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
        queries: [
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
        ],
        favorites: .constant([
            UUID().uuidString: "SELECT * FROM movies WHERE rating > 4.5",
            UUID().uuidString: "SELECT * FROM movies WHERE year = 2015"
        ]),
        toolbarMode: .constant("collections"),
        selectedQuery: .constant("SELECT * FROM movies")
    )
}
