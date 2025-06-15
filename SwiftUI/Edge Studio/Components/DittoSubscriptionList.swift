//
//  DittoSubscriptionList.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/11/25.
//

import SwiftUI

struct DittoSubscriptionList: View {
    @Binding var subscriptions: [DittoSubscription]
    var onEdit: (_ subscription: DittoSubscription) async -> Void
    var onDelete: (_ subscription: DittoSubscription) async throws -> Void
    
    let appState: DittoApp
   
    var body: some View {
#if os(iOS)
        List {
            Section(header: Spacer().frame(height: 24).listRowInsets(EdgeInsets())) {
                ForEach(subscriptions, id: \.id) { subscription in
                    DittoSubscriptionCard(subscription: subscription)
                        .padding(.bottom, 16)
                        .padding(.top, 16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await onEdit(subscription)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await onDelete(subscription)
                                    }catch{
                                        appState.setError(error)
                                    }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    Divider()
                }
            }
        }
        .padding(.top, 4)
#else
        List {
            ForEach(subscriptions, id: \.id) { subscription in
                DittoSubscriptionCard(subscription: subscription)
                    .padding(.bottom, 4)
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await onEdit(subscription)
                            
                        }
                    }
                    .contextMenu {
                        Button("Delete") {
                            Task {
                                do {
                                    try await onDelete(subscription)
                                }catch{
                                    appState.setError(error)
                                }
                            }
                        }
                    }
                Divider()
            }
        }
#endif
    }
}

#Preview {
    DittoSubscriptionList(
        subscriptions: .constant([
            DittoSubscription(
                ["_id": "1",
                 "name": "Example Subscription",
                 "query": "SELECT * FROM example",
                 "args": "{\"arg1\": \"value1\", \"arg2\": \"value2\"}"
                ]),
            DittoSubscription(
                ["_id": "2",
                 "name": "Example Subscription 2",
                 "query": "SELECT * FROM example2",
                 "args": "{\"arg1\": \"value1\", \"arg2\": \"value2\"}"
                ]),
        ]),
        onEdit: { _ in },
        onDelete: { _ in },
        appState: DittoApp()
    )
}
