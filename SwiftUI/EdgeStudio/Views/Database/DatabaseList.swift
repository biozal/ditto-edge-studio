import Combine
import SwiftUI

// iOS-only: macOS uses DatabaseListPanel instead
#if os(iOS)
struct DatabaseList: View {
    let viewModel: ContentView.ViewModel
    let appState: AppState

    var body: some View {
        List {
            Section(header: Spacer().frame(height: 24).listRowInsets(EdgeInsets())) {
                ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
                    DatabaseCard(dittoApp: dittoApp, onEdit: {})
                        .padding(.bottom, 16)
                        .padding(.top, 16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await viewModel.showMainStudio(dittoApp, appState: appState)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteApp(dittoApp, appState: appState)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button(role: .cancel) {
                                viewModel.showAppEditor(dittoApp)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                }
            }
        }
        .padding(.top, 16)
    }
}
#endif
