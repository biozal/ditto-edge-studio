import SwiftUI

// MARK: - MainStudioView Metrics extensions

extension MainStudioView {
    /// Sidebar sub-list for the Metrics menu item
    func metricsSidebarView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView(title: "Metrics")
            List(viewModel.metricsSubItems, id: \.self, selection: $viewModel.selectedMetricsSubItem) { item in
                Label(item, systemImage: item == "App" ? "cpu" : "text.magnifyingglass")
                    .tag(item)
            }
            .listStyle(.sidebar)
        }
    }

    /// Detail view dispatcher for the Metrics menu item
    func metricsDetailView() -> some View {
        Group {
            switch viewModel.selectedMetricsSubItem {
            case "Query":
                QueryMetricsDetailView()
            default:
                AppMetricsDetailView()
            }
        }
        .id(viewModel.selectedMetricsSubItem)
        .transition(.blurReplace)
        .animation(.smooth(duration: 0.25), value: viewModel.selectedMetricsSubItem)
    }

    /// Inspector view for the Metrics menu item
    func metricsInspectorView() -> some View {
        MetricsInspectorView()
    }
}
