//
//  ImportTabView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/24/25.
//

import SwiftUI

struct ImportTabView: View {
    @Binding var viewModel: MainStudioView.ViewModel
    @Binding var isMainStudioViewPresented: Bool
    @EnvironmentObject private var appState: DittoApp
    
    var body: some View {
        ContentUnavailableView(
            "Under Construction",
            systemImage: "exclamationmark.triangle.fill",
            description: Text(
                "The import feature is currently under construction.  Please check back later."
            )
        )
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

#Preview {
    ImportTabView(
        viewModel: .constant(
            MainStudioView.ViewModel(
                DittoAppConfig.new(),
            )
        ),
        isMainStudioViewPresented: .constant(true)
    )
    .environmentObject(DittoApp())
}
