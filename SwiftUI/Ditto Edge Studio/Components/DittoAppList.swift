//
//  DittoAppList.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import SwiftUI
import Combine

struct DittoAppList: View {
  let viewModel: ContentView.ViewModel
  let appState: DittoApp

  var body: some View {
    #if os(iOS)
      List {
        Section(header: Spacer().frame(height: 24).listRowInsets(EdgeInsets())) {
          ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
            DittoAppCard(dittoApp: dittoApp) {}
              .padding(.bottom, 16)
              .padding(.top, 16)
              .contentShape(Rectangle())
              .onTapGesture {
                  Task {
                      await viewModel.showMainStudio(dittoApp, appState: appState)
                  }
              }
              .swipeActions(edge: .trailing) {
                Button(role: .cancel) {
                  viewModel.showAppEditor(dittoApp)
                } label: {
                  Label("Edit", systemImage: "pencil")
                }
              }
          }
        }
      }
      .padding(.top, 16)
    #else
      List {
        ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
          DittoAppCard(dittoApp: dittoApp) {}
            .padding(.bottom, 16)
            .padding(.top, 16)
            .contentShape(Rectangle())
            .onTapGesture {
              Task {
                await viewModel.showMainStudio(
                  dittoApp,
                  appState: appState)
              }
            }
            .contextMenu {
              Button("Edit") {
                viewModel.showAppEditor(dittoApp)
              }
            }
        }
      }
    #endif
  }
}
