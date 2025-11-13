//
//  RegisterCollectionModal.swift
//  Edge Debug Helper
//
//  Modal for registering a new collection in Edge Studio
//

import SwiftUI

struct RegisterCollectionModal: View {
    @Binding var isPresented: Bool
    let onRegister: (String) async -> Void

    @State private var collectionName: String = ""
    @State private var isRegistering: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Register Collection")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                Text("Collection Name")
                    .font(.headline)

                TextField("Enter collection name", text: $collectionName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .disabled(isRegistering)
                    .onChange(of: collectionName) { _, _ in
                        // Clear error when user types
                        errorMessage = nil
                    }

                // Info box
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("This will register the collection in Edge Studio's tracking. Collections may exist in your Ditto database without being registered in Edge Studio.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.1))
                )

                // Error message
                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )
                }
            }
            .padding(.bottom, 20)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                .disabled(isRegistering)

                Spacer()

                Button("Register") {
                    registerCollection()
                }
                .keyboardShortcut(.return)
                .disabled(!isValidCollectionName || isRegistering)
            }
            .padding(.top, 12)
        }
        .padding(30)
        .frame(width: 450)
        .onAppear {
            // Auto-focus the text field when modal appears
            isTextFieldFocused = true
        }
    }

    private var isValidCollectionName: Bool {
        let trimmed = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Only allow letters, numbers, and underscores
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func registerCollection() {
        let trimmed = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorMessage = "Collection name cannot be empty"
            return
        }

        guard trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            errorMessage = "Collection name can only contain letters, numbers, and underscores"
            return
        }

        isRegistering = true
        errorMessage = nil

        Task {
            await onRegister(trimmed)

            await MainActor.run {
                isRegistering = false
                isPresented = false
            }
        }
    }
}

#Preview {
    RegisterCollectionModal(
        isPresented: .constant(true),
        onRegister: { collectionName in
            print("Registering collection: \(collectionName)")
        }
    )
}
