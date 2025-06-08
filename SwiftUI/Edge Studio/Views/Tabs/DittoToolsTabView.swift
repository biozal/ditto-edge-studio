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
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
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
            .frame(minWidth: 200, idealWidth: 320, maxWidth: 400)
        } detail: {
            ToolsViewer(selectedDataTool: $viewModel.selectedDataTool)
        }
        #if os(iOS)
            .navigationSplitViewColumnWidth(300)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.selectedApp.name).font(.headline).bold()
                }
            }
        #else
            .navigationSplitViewStyle(.automatic)
            .navigationSplitViewColumnWidth(min: 200, ideal: 320, max: 400)
        #endif
    }
}

extension DittoToolsTabView {
    @Observable
    class ViewModel {
        let selectedApp: DittoAppConfig
        
        // Tools Menu Options
        // TODO remove magic strings
        var dittoToolsFeatures = ["Presence Viewer", "Permissions Health", "Disk Usage"]
        var selectedDataTool: String?
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
        }
    }
}

#Preview {
    DittoToolsTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new())
    .environmentObject(DittoApp())
}

