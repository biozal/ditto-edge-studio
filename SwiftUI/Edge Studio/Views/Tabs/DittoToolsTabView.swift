//
//  DittoToolsTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/22/25.
//
import SwiftUI

struct DittoToolsTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    
    @State var viewModel: DittoToolsTabView.ViewModel
    
    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig) {
            self._isMainStudioViewPresented = isMainStudioViewPresented
            self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

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
                        ForEach(viewModel.dittoToolsFeatures, id: \.self) {
                            tool in
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
            ToolsViewer(selectedDataTool: $viewModel.selectedDataTool)
        }
        #if os(iPadOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
            }
        #elseif os(macOS)
            .toolbar {
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
            }
        #endif
    }
}

extension DittoToolsTabView {
    @Observable
    class ViewModel {
        let selectedApp: DittoAppConfig
        
        // Tools Menu Options
        // TODO remove magic strings
        var dittoToolsFeatures = ["Presence Viewer", "Permissions Health", "Presence Degration", "Disk Usage"]
        var selectedDataTool: String?
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
        }
        
        func closeSelectedApp() async {
            await DittoManager.shared.closeDittoSelectedApp()
        }
    }
}

#Preview {
    DittoToolsTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new())
    .environmentObject(DittoApp())
}

