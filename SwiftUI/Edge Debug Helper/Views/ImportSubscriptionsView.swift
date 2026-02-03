import SwiftUI

struct ImportSubscriptionsView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var viewModel: ImportSubscriptionsViewModel

    init(isPresented: Binding<Bool>, existingSubscriptions: [DittoSubscription], selectedAppId: String) {
        self._isPresented = isPresented
        self._viewModel = State(initialValue: ImportSubscriptionsViewModel(
            existingSubscriptions: existingSubscriptions,
            selectedAppId: selectedAppId
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Import Subscriptions from Devices")
                .font(.title2)
                .bold()
                .padding(.top)

            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading device subscriptions...")
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                ContentUnavailableView(
                    "Error Loading Subscriptions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                Spacer()
            } else if viewModel.importableSubscriptions.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No New Subscriptions Found",
                    systemImage: "checkmark.circle",
                    description: Text("All device subscriptions are already imported")
                )
                Spacer()
            } else {
                subscriptionsList
            }

            // Import status
            if viewModel.isImporting {
                ProgressView(viewModel.importStatus)
                    .padding()
            }

            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .disabled(viewModel.isImporting)

                Spacer()

                Text("\(viewModel.selectedCount) selected")
                    .foregroundColor(.secondary)

                Button("Import Selected") {
                    Task {
                        do {
                            try await viewModel.importSelectedSubscriptions()
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                            isPresented = false
                        } catch {
                            appState.setError(error)
                        }
                    }
                }
                .disabled(viewModel.selectedCount == 0 || viewModel.isImporting)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
        .task {
            await viewModel.loadDevicesAndSubscriptions()
        }
    }

    private var subscriptionsList: some View {
        List {
            ForEach(viewModel.importableSubscriptions) { subscription in
                HStack(alignment: .top, spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { subscription.isSelected },
                        set: { _ in viewModel.toggleSelection(for: subscription.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(subscription.collectionName)
                            .font(.headline)

                        Text(subscription.query)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        HStack {
                            Label(subscription.deviceName, systemImage: "desktopcomputer")
                            Text("•")
                            Text(subscription.deviceInfo)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
