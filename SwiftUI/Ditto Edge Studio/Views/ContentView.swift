import Combine
//
//  ContentView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: DittoApp
    @State private var viewModel: ContentView.ViewModel = ViewModel()
    @State private var showingAddApp = false

    var body: some View {
        VStack {
            Button(action: {
                showingAddApp = true
            }) {
                Label("Add New App", systemImage: "plus")
            }
            .padding(.top)
        }
        .padding()
        .sheet(isPresented: $showingAddApp) {
            AddAppView()
        }
    }
}

extension ContentView {
    @Observable
    @MainActor
    class ViewModel {
        @ObservationIgnored private var cancellables = Set<AnyCancellable>()

        var dittoApps: [DittoAppConfig] = []
        var isLoading = false

        //used for editor
        var isPresented = false
        var dittoAppToEdit: DittoAppConfig?

        init() {
            // Observe changes to DittoService's planets
            Task { @MainActor in
                
                DittoManager.shared.$dittoAppConfigs
                    .receive(on: RunLoop.main)
                    .sink { [weak self] updatedApps in
                        self?.dittoApps = updatedApps
                    }
                    .store(in: &cancellables)
                 
            }
        }

        func showAppEditor(_ dittoApp: DittoAppConfig) {
            dittoAppToEdit = dittoApp
            isPresented = true
        }
    }
}

#Preview {
    ContentView()
}
