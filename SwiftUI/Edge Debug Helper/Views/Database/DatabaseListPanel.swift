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
                            .onTapGesture {
                                Task { await viewModel.showMainStudio(dittoApp, appState: appState) }
                            }
                            .contextMenu {
                                Button {
                                    viewModel.showAppEditor(dittoApp)
                                } label: { Label("Edit", systemImage: "pencil") }
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
}
