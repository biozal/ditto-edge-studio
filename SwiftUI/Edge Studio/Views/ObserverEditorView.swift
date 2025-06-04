//
//  AddObserverView.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 6/2/25.
//

import SwiftUI

struct ObserverEditorView: View {
    @EnvironmentObject private var appState: DittoApp
    @StateObject private var viewModel: ViewModel
    
    init(isPresented: Binding<Bool>, dittoAppConfig: DittoAppConfig) {
        self._viewModel = StateObject(wrappedValue: ViewModel(isPresented: isPresented,
                                              selectedApp: dittoAppConfig))
    }
    var body: some View {
        Text("Observer Editor View")
    }
}

#Preview {
    ObserverEditorView(
        isPresented: .constant(true),
        dittoAppConfig: DittoAppConfig.new()
    )
}


extension ObserverEditorView {
    class ViewModel : ObservableObject {
        @Binding var presentationBinding: Bool
        let selectedApp: DittoAppConfig
        
        var isPresented: Bool {
            get { presentationBinding }
            set { presentationBinding = newValue }
        }
        
        init (isPresented: Binding<Bool>, selectedApp: DittoAppConfig) {
            self._presentationBinding = isPresented
            self.selectedApp = selectedApp
        }
    }
}

