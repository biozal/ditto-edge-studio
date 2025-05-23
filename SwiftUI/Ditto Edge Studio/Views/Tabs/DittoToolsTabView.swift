//
//  DittoToolsTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/22/25.
//
import SwiftUI

struct DittoToolsTabView : View {
    @Binding var viewModel: MainStudioView.ViewModel
    @Binding var isMainStudioViewPresented: Bool
    @EnvironmentObject private var appState: DittoApp

    var body: some View {
        NavigationSplitView {
            List {
#if os(macOS)
                Section(
                    header:
                        Text("Ditto Tools")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.bottom, 5)
                ) {
                    ForEach(viewModel.dittoToolsFeatures, id: \.self) { tool in
                        Text(tool)
                            .onTapGesture {
                                viewModel.selectedDataTool = tool
                            }
                    }
                }
#else
                ForEach(viewModel.dittoToolsFeatures, id: \.self) { tool in
                    Text(tool)
                        .onTapGesture {
                            viewModel.selectedDataTool = tool
                        }
                }
#endif
            }
            .navigationTitle("Ditto Tools")
        } detail: {
            // Second Column - Metrics in Category
            if let tool = viewModel.selectedDataTool {
                Text(tool)
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
        .toolbar {
            #if os(iPadOS)
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
            #endif
            #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task {
                            await viewModel.closeSelectedApp()
                            isMainStudioViewPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            #endif
        }
    }
}
