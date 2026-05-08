import SwiftUI

struct DatabaseListPanel: View {
    let viewModel: ContentView.ViewModel
    let appState: AppState
    @State private var selectedId: String?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let initError = viewModel.sqlCipherInitError {
                sqlCipherInitErrorView(initError)
            } else if viewModel.dittoApps.isEmpty {
                VStack(spacing: 12) {
                    FontAwesomeText(icon: DataIcon.databaseThin, size: 40, color: .secondary)
                    Text("No database configurations found")
                        .foregroundColor(.primary)
                    Text(
                        "Use \"+ Database Config\" button to add one.  \nNew to Ditto?  Click Help -> User Guide for \nmore information on how to get started."
                    )
                    .foregroundColor(Color.Ditto.papyrusWhite)
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedId) {
                    ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
                        DatabaseListRow(dittoApp: dittoApp)
                            .tag(dittoApp._id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(
                                selectedId == dittoApp._id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .overlay(alignment: .trailing) {
                                if viewModel.openingDatabaseId == dittoApp._id {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 12)
                                        .accessibilityIdentifier("DatabaseOpeningSpinner")
                                }
                            }
                            .opacity(
                                (viewModel.openingDatabaseId != nil &&
                                    viewModel.openingDatabaseId != dittoApp._id) ? 0.5 : 1.0
                            )
                            .allowsHitTesting(viewModel.openingDatabaseId == nil)
                            .onTapGesture {
                                Task { await viewModel.showMainStudio(dittoApp, appState: appState) }
                            }
                            .contextMenu {
                                Button {
                                    viewModel.showAppEditor(dittoApp)
                                } label: { Label("Edit", systemImage: "pencil") }
                                Button {
                                    Task { await viewModel.showQRCode(dittoApp) }
                                } label: { Label("Show QR Code", systemImage: "qrcode") }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteApp(dittoApp, appState: appState) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .accessibilityIdentifier("AppCard_\(dittoApp.name)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("DatabaseList")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Distinct error/retry state for SQLCipher initialization failures.
    private func sqlCipherInitErrorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Database Storage Unavailable")
                .foregroundColor(.primary)
            Text(error.localizedDescription)
                .foregroundColor(Color.Ditto.papyrusWhite)
                .font(.caption)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadApps(appState: appState) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.dittoYellow)
            .accessibilityIdentifier("RetrySQLCipherInitButton")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
