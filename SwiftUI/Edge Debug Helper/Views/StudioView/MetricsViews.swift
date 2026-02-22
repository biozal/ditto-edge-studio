import SwiftUI

// MARK: - MainStudioView Metrics extensions

extension MainStudioView {
    /// Sidebar sub-list for the Metrics menu item
    func metricsSidebarView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView(title: "Metrics")
            #if os(macOS)
            List(viewModel.metricsSubItems, id: \.self, selection: $viewModel.selectedMetricsSubItem) { item in
                Label(item, systemImage: item == "App" ? "cpu" : "text.magnifyingglass")
                    .tag(item)
            }
            .listStyle(.sidebar)
            #else
            List(viewModel.metricsSubItems, id: \.self) { item in
                Label(item, systemImage: item == "App" ? "cpu" : "text.magnifyingglass")
                    .onTapGesture {
                        viewModel.selectedMetricsSubItem = item
                    }
                    .listRowBackground(
                        viewModel.selectedMetricsSubItem == item
                            ? Color.accentColor.opacity(0.2)
                            : Color.clear
                    )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            #endif
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
}
