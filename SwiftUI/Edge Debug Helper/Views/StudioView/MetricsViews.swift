import SwiftUI

// MARK: - MainStudioView Metrics extensions

extension MainStudioView {
    /// Detail view dispatcher for the Metrics menu item
    func metricsDetailView() -> some View {
        Group {
            switch viewModel.selectedMetricsSubItem {
            case "Query":
                QueryMetricsDetailView()
            default:
                #if os(macOS)
                AppMetricsDetailView()
                #else
                QueryMetricsDetailView()
                #endif
            }
        }
        .id(viewModel.selectedMetricsSubItem)
        .transition(.blurReplace)
        .animation(.smooth(duration: 0.25), value: viewModel.selectedMetricsSubItem)
    }
}
