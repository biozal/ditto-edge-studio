 #if os(iOS)
                AnyView(
                  List {
                    Section(header: Spacer().frame(height: 24).listRowInsets(EdgeInsets())) {
                      ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
                        DittoAppCard(dittoApp: dittoApp) {}
                          .contentShape(Rectangle())
                          .onTapGesture {
                            viewModel.showMainStudio(dittoApp)
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
                  .padding(.top, 16))
              #else
                AnyView(
                  List {
                    ForEach(viewModel.dittoApps, id: \._id) { dittoApp in
                      DittoAppCard(dittoApp: dittoApp) {}
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
                  })
              #endif