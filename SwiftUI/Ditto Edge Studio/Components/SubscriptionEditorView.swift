//
//  SubscriptionEditorView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import Combine
import SwiftUI

struct SubscriptionEditorView: View {
    @State private var name: String
    @State private var query: String
    @State private var arguments: String
    
    let subscription: DittoSubscription
    let onSave: (String, String, String?) -> Void
    let onCancel: () -> Void
    
    init(
        _ subscription: DittoSubscription,
        onSave: @escaping (String, String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.subscription = subscription
        self._name = State(initialValue: subscription.name)
        self._query = State(initialValue: subscription.query)
        self._arguments = State(initialValue: subscription.args?.description ?? "")
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        Form {
            Section {
                Text("Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("", text: $name)
                    .padding(.bottom, 10)
#if os(macOS)
                Divider()
                    .padding(.bottom, 10)
#endif
                Text("Query")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $query)
                    .frame(height: 50)
                Text("Ex: SELECT * FROM collectionName")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
#if os(macOS)
                Divider()
                    .padding(.bottom, 10)
#endif
                Text("Arguments")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $arguments)
                    .frame(height: 150)
                Text("JSON String Format - Ex: [{\"key\": \"value\"}]")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
#if os(macOS)
                Divider()
                    .padding(.bottom, 10)
#endif
            }
            Section {
                HStack(spacing: 16) {
                    Button(action: {
                        onSave(name, query, arguments.isEmpty ? nil : arguments)
                    }) {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle(subscription.name.isEmpty ? "New Subscription" : "Edit Subscription")
    }
}
