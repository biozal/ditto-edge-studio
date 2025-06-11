//
//  MongoTabView.swift
//  Edge Studio
//
//  Created by Aaron LaBeau on 6/11/25.
//

import SwiftUI

struct MongoTabView: View {
    @EnvironmentObject private var appState: DittoApp
    @Binding var isMainStudioViewPresented: Bool
    @State private var viewModel: MongoTabView.ViewModel
    
    init(
        isMainStudioViewPresented: Binding<Bool>,
        dittoAppConfig: DittoAppConfig
    ) {
        self._isMainStudioViewPresented = isMainStudioViewPresented
        self._viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }
    var body: some View {
        NavigationSplitView {
            MongoSidebarView(mongoCollections: $viewModel.mongoCollections)
                .padding(.top, 20)
            #if os(macOS)
                .frame(minWidth: 250, idealWidth: 320, maxWidth: 400)
            #endif
        } detail: {
            #if os(macOS)
            VSplitView {
                VStack{
                    Text("Top Half")
                        .padding(.top, 10)
                    Spacer()
                }
                //bottom half
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults
                )
            }
            #else
            VStack {
                VStack {
                    Text("Top Half")
                    Spacer()
                }
                .frame(minHeight: 100, idealHeight: 150, maxHeight: 200)
                //bottom half
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.selectedApp.name).font(.headline).bold()
            }
        }
        #endif
    }
}

extension MongoTabView {
    @Observable
    @MainActor
    class ViewModel {
        let selectedApp: DittoAppConfig
        
        var mongoCollections: [String] = []
        //results view
        var jsonResults: [String]
        
        init(_ dittoAppConfig: DittoAppConfig) {
            self.selectedApp = dittoAppConfig
            
            //query results section
            self.jsonResults = []
            
            Task {
                mongoCollections = await MongoManager.shared.collections
            }
        }
    }
}

#Preview {
    MongoTabView(
        isMainStudioViewPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    ).environmentObject(DittoApp())
}
