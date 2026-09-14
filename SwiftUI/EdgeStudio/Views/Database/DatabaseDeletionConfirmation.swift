import SwiftUI

/// The confirmation gate for deleting a database configuration.
///
/// `ContentView.ViewModel.deleteApp` only *stages* `appPendingDeletion`; the only code
/// that actually deletes is `confirmPendingAppDeletion`, and this dialog is the only
/// thing that calls it.
///
/// **The item is passed through `presenting:` into the action, never re-read from the
/// view model.** That is the whole reason Delete used to do nothing at all. Tapping the
/// button dismisses the dialog, which drives `isPresented` to false, which runs the
/// binding's setter and clears `appPendingDeletion` — *before* the action's `Task` gets
/// to read it. `confirmPendingAppDeletion` then hit its `guard let … else { return }`
/// and returned silently, never reaching the repository, which is why the failure left
/// no trace in the logs either. `presenting:` hands the value straight to the closure,
/// so the dismissal can no longer race it.
///
/// Packaging the gate as one modifier keeps that subtlety in one place rather than
/// copied into every host that offers a delete affordance.
struct DatabaseDeletionConfirmation: ViewModifier {
    let viewModel: ContentView.ViewModel
    let appState: AppState

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \(viewModel.appPendingDeletion?.name ?? "Database")?",
            isPresented: Binding(
                get: { viewModel.appPendingDeletion != nil },
                set: {
                    if !$0 {
                        viewModel.appPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: viewModel.appPendingDeletion
        ) { pendingConfig in
            Button("Delete", role: .destructive) {
                // `pendingConfig` is captured here, so clearing the staged value on
                // dismissal cannot pull it out from under this action.
                Task { await viewModel.confirmAppDeletion(pendingConfig, appState: appState) }
            }
            .accessibilityIdentifier("ConfirmDeleteDatabaseButton")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This deletes the local database and all its Edge Studio data. This cannot be undone.")
        }
    }
}

extension View {
    /// Attach the destructive-delete confirmation gate.
    ///
    /// Required on every view that offers a delete affordance for a database
    /// configuration — see `DatabaseDeletionConfirmation` for why.
    func databaseDeletionConfirmation(
        viewModel: ContentView.ViewModel,
        appState: AppState
    ) -> some View {
        modifier(DatabaseDeletionConfirmation(viewModel: viewModel, appState: appState))
    }
}
