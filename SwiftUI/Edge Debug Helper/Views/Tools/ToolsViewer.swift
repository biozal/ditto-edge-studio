import SwiftUI
import DittoSwift

struct ToolsViewer: View{
    @Binding var selectedDataTool: String?
    @State private var ditto: Ditto?
    var body: some View {
        ZStack{
            // Second Column - Metrics in Category
            if let tool = self.selectedDataTool {
                switch tool {
                case "Presence Viewer":
                    if let ditto = ditto {
                        PresenceViewer(ditto: ditto)
                    } else {
                        ToolsErrorView()
                    }
                case "Peers List":
                        if let ditto = ditto {
                            DittoPeersListView(ditto: ditto)
                        } else {
                            ToolsErrorView()
                        }
                case "Permissions Health":
                    PermissionsHealthViewer()
                case "Disk Usage":
                    if let ditto = ditto {
                        DiskUsageViewer(ditto: ditto)
                    } else {
                        ToolsErrorView()
                    }
                default:
                    ContentUnavailableView(
                        "Tool Not Implemented",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(
                            "This tool hasn't been implemented yet."
                        )
                    )
                }
            } else {
                ContentUnavailableView(
                    "Select Tool",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "Select a tool from the list on the left."
                    )
                )
            }
        }
        .task {
            ditto = await DittoManager.shared.dittoSelectedApp
        }
    }
}
