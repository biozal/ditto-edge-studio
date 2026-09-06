import SwiftUI

@MainActor
struct DatabaseEditorView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool
    /// Optional binding so the host (`ContentView`) can disable interactive
    /// dismiss while the form has uncommitted changes. When `nil`, the editor
    /// still surfaces its own confirmation dialog on Cancel.
    @Binding var hasUnsavedChanges: Bool
    @State private var viewModel: ViewModel
    /// Drives the "Discard changes?" confirmation when the user taps Cancel
    /// with an unsaved form. Cleared on every dismissal path.
    @State private var showDiscardConfirmation = false

    init(
        isPresented: Binding<Bool>,
        hasUnsavedChanges: Binding<Bool> = .constant(false),
        dittoAppConfig: DittoConfigForDatabase
    ) {
        _isPresented = isPresented
        _hasUnsavedChanges = hasUnsavedChanges
        _viewModel = State(initialValue: ViewModel(dittoAppConfig))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                #if os(macOS)
                HStack {
                    Text(viewModel.isNewItem ? "Register Database" : "Edit Database")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.bottom, 12)
                // The title is fixed chrome: never let the greedy Form below
                // compress it, which previously clipped the glyphs in half.
                .fixedSize(horizontal: false, vertical: true)
                #endif

                Form {
                    HStack {
                        Spacer()
                        DittoSegmentedPicker(
                            options: AuthMode.allCases,
                            selection: $viewModel.mode
                        ) { $0.displayName }
                            .frame(maxWidth: 300)
                            .accessibilityIdentifier("AuthModePicker")
                        Spacer()
                    }
                    #if os(macOS)
                    // Padding rather than a Spacer row: under `.grouped` an empty
                    // Spacer renders as a visible empty cell.
                    .padding(.bottom, 12)
                    #endif

                    Section("Basic Information") {
                        TextField("Name", text: $viewModel.name)
                            .lineLimit(1)
                            .padding(.bottom, 10)
                            .accessibilityIdentifier("NameTextField")
                    }

                    Section("Authorization Information") {
                        // Read-only once registered. The Database ID is the key four
                        // child tables reference with `ON DELETE CASCADE` and no
                        // `ON UPDATE`, so changing it raised `FOREIGN KEY constraint
                        // failed` for any database that had ever run a query — failing
                        // the whole save and losing the name/token/scope edits submitted
                        // with it. It also names the on-disk Ditto store directory
                        // (`DittoManager.localDirectoryPath`), so changing it would
                        // orphan the local data. Delete and re-register to change it.
                        TextField("Database ID", text: $viewModel.databaseId)
                        #if os(macOS)
                            .textFieldStyle(.roundedBorder)
                        #endif
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .trimOnPaste($viewModel.databaseId)
                            .disabled(!viewModel.isNewItem)
                            .padding(.bottom, viewModel.isNewItem ? 5 : 2)
                            .accessibilityIdentifier("DatabaseIdTextField")

                        if !viewModel.isNewItem {
                            Text(
                                "The Database ID cannot be changed after registration. To use a different ID, delete this database and register it again."
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 5)
                            .accessibilityIdentifier("DatabaseIdLockedCaption")
                        }

                        authTokenField(for: viewModel.mode)
                    }

                    modeSpecificSections(for: viewModel.mode)

                    // Info panel lives INSIDE the form so it scrolls with everything
                    // else. Gated on `isNewItem` rather than `databaseId.isEmpty`:
                    // that value changes as the user types, which would yank a ~90pt
                    // row out of the middle of the scroll content mid-keystroke.
                    if viewModel.isNewItem {
                        registrationInfoPanel
                    }
                }
                #if os(macOS)
                // The default macOS form style is `.columns`, which is a layout
                // container, not a scroll view — the editor previously fit only
                // because its captions happened to wrap. `.grouped` scrolls, which is
                // what the Advanced Configuration section needs.
                .formStyle(.grouped)
                #endif
                // The Form must be the ONLY vertically-greedy child, so the sheet's
                // fixed height acts as a viewport and the form scrolls inside it. A
                // sibling Spacer here previously split the residual space and
                // reintroduced the overflow that clipped the header.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #if os(macOS)
            .padding(.leading, 16)
            .padding(.trailing, 24)
            .padding(.vertical, 16)
            #endif
            #if os(iOS)
            .navigationTitle(viewModel.isNewItem ? "Register Database" : "Edit Database")
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        attemptCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .accessibilityIdentifier("CancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            // Dismiss only on success: a failed write used to close the
                            // sheet anyway, discarding everything behind a transient alert.
                            if await viewModel.save(appState: appState) {
                                isPresented = false
                            }
                        }
                    }
                    .disabled(viewModel.databaseId.isEmpty ||
                        viewModel.name.isEmpty ||
                        viewModel.developmentToken.isEmpty ||
                        viewModel.hasAdvancedValidationErrors)
                    .accessibilityIdentifier("SaveButton")
                }
            }
        }
        .onAppear {
            // Sync the host's binding with whatever the view model currently
            // reports — covers the rare case where `@State` survives across a
            // sheet re-presentation with an updated config.
            hasUnsavedChanges = viewModel.hasUnsavedChanges
            // Expand when the section is why Save is disabled: the corrupt-scope banner,
            // its discard toggle and the row errors all live inside it, so a collapsed
            // section left the user with a greyed-out Save and only a small red hint.
            if viewModel.hasAdvancedValidationErrors {
                viewModel.isAdvancedExpanded = true
            }
            let model = viewModel
            Task { await model.loadLastApplyOutcome() }
        }
        .onChange(of: viewModel.hasUnsavedChanges) { _, newValue in
            hasUnsavedChanges = newValue
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                hasUnsavedChanges = false
                isPresented = false
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your edits to this database configuration will be lost.")
        }
    }

    /// Routes the Cancel button: confirms the discard intent when the form has
    /// unsaved edits, otherwise dismisses immediately. Used for the explicit
    /// Cancel toolbar action on both platforms; iOS swipe-to-dismiss is gated
    /// separately by `.interactiveDismissDisabled` on the hosting sheet.
    private func attemptCancel() {
        if viewModel.hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            hasUnsavedChanges = false
            isPresented = false
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private func authTokenField(for mode: AuthMode) -> some View {
        switch mode {
        case .development:
            TextField("Development token", text: $viewModel.developmentToken)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .trimOnPaste($viewModel.developmentToken)
                .padding(.bottom, 10)
                .accessibilityIdentifier("TokenTextField")
        case .smallPeerOnly:
            TextField("Offline Token", text: $viewModel.developmentToken)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .trimOnPaste($viewModel.developmentToken)
                .padding(.bottom, 5)
                .accessibilityIdentifier("TokenTextField")

            Text("Required for sync activation in Small Peer Only mode.\nObtain from https://portal.ditto.live")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func modeSpecificSections(for mode: AuthMode) -> some View {
        switch mode {
        case .smallPeerOnly:
            secretKeySection()
        case .development:
            serverInformationSection()
            httpApiSection()
        }
        advancedConfigurationSections()
        developerOptionsSection()
    }

    /// The info callout shown while registering a new database.
    private var registrationInfoPanel: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 16))

            Text(
                "This information comes from the [Ditto Portal](https://portal.ditto.live) and is required in order to register a Ditto Database."
            )
            .font(.callout)
            .foregroundStyle(.primary)
            // Lets the text wrap instead of demanding its full single-line width,
            // which is what previously pushed content wider than the sheet.
            .fixedSize(horizontal: false, vertical: true)
            .tint(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Advanced Configuration

    /// A plain `Section` with an explicit disclosure **row**, not `Section(isExpanded:)`.
    ///
    /// The built-in section triangle is not reachable by XCUITest — its identifier lands
    /// on a non-interactive header, so the UI test's tap did nothing and every layout
    /// assertion after it silently passed. Owning the expansion state and the control
    /// makes the section automatable and behaves identically for a user.
    private func advancedConfigurationSections() -> some View {
        Section {
            Button {
                viewModel.isAdvancedExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: viewModel.isAdvancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Advanced Configuration")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(viewModel.advancedSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.hasAdvancedValidationErrors {
                        Text("needs attention")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AdvancedConfigDisclosure")

            if viewModel.isAdvancedExpanded {
                // No `Divider()` between these: inside a `.grouped` form it renders as an
                // empty cell rather than a hairline. The section headings separate them.
                syncScopesContent()

                startupSettingsContent()

                HStack {
                    if viewModel.canUndoResetToDefaults {
                        Button("Undo Reset") {
                            viewModel.undoResetToDefaults()
                        }
                        .accessibilityIdentifier("UndoResetButton")
                    } else {
                        Button("Reset to SDK Defaults") {
                            viewModel.resetAdvancedToDefaults()
                        }
                        .accessibilityIdentifier("ResetToDefaultsButton")
                    }
                    Spacer()
                }
                .padding(.top, 4)

                if viewModel.resetToDefaultsRequested {
                    Text(
                        "System settings will be restored to Ditto's defaults. If this database " +
                            "is currently open, that happens when you save; otherwise it takes effect " +
                            "the next time you open it."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func syncScopesContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasCorruptSyncScopes {
                VStack(alignment: .leading, spacing: 6) {
                    Text("⚠️ The saved sync scopes for this database could not be read.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This database will not open until you re-enter the scopes below, or confirm that losing them is acceptable.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Discard the unreadable sync scopes", isOn: $viewModel.discardCorruptSyncScopes)
                        .font(.caption2)
                        .accessibilityIdentifier("DiscardCorruptScopesToggle")
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
                .accessibilityIdentifier("CorruptSyncScopesBanner")
            }

            Text("COLLECTION SYNC SCOPES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Control where each user collection may synchronize. Changes apply the next time this connection starts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.collectionSyncScopes) { row in
                syncScopeRow(row: row)
            }

            Button("+ Add collection") {
                viewModel.addSyncScope()
            }
            .accessibilityIdentifier("AddSyncScopeButton")
            .disabled(viewModel.collectionSyncScopes.count >= AdvancedSettingsValidator.maxRowCount)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SyncScope.allCases, id: \.self) { scope in
                    Text("• **\(scope.displayName)** — \(scope.explanation)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)

            Text("Sync scopes and startup settings are not included when sharing a database by QR code.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    /// One scope row. `ViewThatFits` because the trailing column of a macOS form is
    /// roughly half the sheet width, and an iPad sheet in Slide Over is ~320pt — three
    /// controls side by side simply do not fit there.
    @ViewBuilder
    private func syncScopeRow(row: CollectionSyncScope) -> some View {
        let error = viewModel.syncScopeError(id: row.id)

        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    scopeCollectionField(id: row.id)
                        .frame(minWidth: 180)
                    scopePicker(id: row.id)
                        .frame(minWidth: 150)
                    removeButton { viewModel.removeSyncScope(id: row.id) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    scopeCollectionField(id: row.id)
                    HStack {
                        scopePicker(id: row.id)
                        Spacer()
                        removeButton { viewModel.removeSyncScope(id: row.id) }
                    }
                }
            }

            if let error {
                Text(error.message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("SyncScopeRow_\(row.id.uuidString)")
    }

    @ViewBuilder
    private func scopeCollectionField(id: UUID) -> some View {
        TextField("Collection", text: bindingForScopeCollection(id: id))
        #if os(macOS)
            .textFieldStyle(.roundedBorder)
        #endif
            .lineLimit(1)
    }

    private func scopePicker(id: UUID) -> some View {
        Picker("Scope", selection: bindingForScope(id: id)) {
            ForEach(SyncScope.allCases, id: \.self) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func startupSettingsContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STARTUP SYSTEM SETTINGS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Applied after Ditto opens and before sync or subscriptions start.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(viewModel.startupSettings) { row in
                startupSettingRow(row: row)
            }

            Button("+ Add startup setting") {
                viewModel.addStartupSetting()
            }
            .accessibilityIdentifier("AddStartupSettingButton")
            .disabled(viewModel.startupSettings.count >= AdvancedSettingsValidator.maxRowCount)

            Text(
                "Enter a parameter name for every startup setting. Values are applied exactly as typed — Edge Studio does not validate that a parameter exists."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            // Outcome of the most recent open. Without this, a rejected parameter — or
            // scopes that were applied but could not be verified — existed only as a
            // line in the log file.
            if !viewModel.lastApplyFailures.isEmpty || viewModel.lastApplyScopesUnverified {
                VStack(alignment: .leading, spacing: 2) {
                    if viewModel.lastApplyScopesUnverified {
                        Text("Sync scopes were applied but could not be verified when this database was last opened.")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !viewModel.lastApplyFailures.isEmpty {
                        Text("Not applied when this database was last opened:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                        ForEach(viewModel.lastApplyFailures, id: \.self) { failure in
                            Text("• \(failure)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityIdentifier("AdvancedApplyFailures")
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func startupSettingRow(row: StartupSetting) -> some View {
        let error = viewModel.startupSettingError(id: row.id)

        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    settingNameField(id: row.id).frame(minWidth: 170)
                    settingTypePicker(id: row.id).frame(minWidth: 110)
                    settingValueControl(id: row.id, type: row.type).frame(minWidth: 150)
                    removeButton { viewModel.removeStartupSetting(id: row.id) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    settingNameField(id: row.id)
                    HStack(spacing: 8) {
                        settingTypePicker(id: row.id)
                        Spacer()
                        removeButton { viewModel.removeStartupSetting(id: row.id) }
                    }
                    settingValueControl(id: row.id, type: row.type)
                }
            }

            if let error {
                Text(error.message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.isSensitiveRow(id: row.id) {
                Toggle(isOn: bindingForAcknowledgement(id: row.id)) {
                    Text("I understand this parameter can expose data on the network or reduce durability.")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("StartupSettingAcknowledge_\(row.id.uuidString)")
            }
        }
        .accessibilityIdentifier("StartupSettingRow_\(row.id.uuidString)")
    }

    @ViewBuilder
    private func settingNameField(id: UUID) -> some View {
        TextField("Parameter", text: bindingForSettingParameter(id: id))
        #if os(macOS)
            .textFieldStyle(.roundedBorder)
        #endif
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
    }

    private func settingTypePicker(id: UUID) -> some View {
        Picker("Type", selection: bindingForSettingType(id: id)) {
            ForEach(StartupSettingType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func settingValueControl(id: UUID, type: StartupSettingType) -> some View {
        if type == .boolean {
            Picker("Value", selection: bindingForSettingValue(id: id)) {
                ForEach(StartupSetting.booleanValues, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } else {
            TextField("Value", text: bindingForSettingValue(id: id))
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .font(type == .json ? .system(.body, design: .monospaced) : .body)
                .lineLimit(1)
            #if os(iOS)
                // Not `.numbersAndPunctuation`: it has no `e`, and system parameters
                // include values like 1.0000000000000001e-09.
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
            #endif
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button("Remove", role: .destructive, action: action)
            .buttonStyle(.borderless)
            .font(.caption)
    }

    // MARK: Row bindings

    //
    // Rows are iterated by value and their fields bound through the view model by
    // index, resolved on access. Binding-based `ForEach($rows)` iteration crashes when
    // a row removes itself: the row body owns an index-derived binding that the
    // removal invalidates before `ForEach` re-diffs.

    private func bindingForScopeCollection(id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.collectionSyncScopes.first { $0.id == id }?.collection ?? "" },
            set: { newValue in
                guard let index = viewModel.collectionSyncScopes.firstIndex(where: { $0.id == id }) else { return }
                viewModel.collectionSyncScopes[index].collection = newValue
            }
        )
    }

    private func bindingForScope(id: UUID) -> Binding<SyncScope> {
        Binding(
            get: { viewModel.collectionSyncScopes.first { $0.id == id }?.scope ?? .allPeers },
            set: { newValue in
                guard let index = viewModel.collectionSyncScopes.firstIndex(where: { $0.id == id }) else { return }
                viewModel.collectionSyncScopes[index].scope = newValue
            }
        )
    }

    private func bindingForSettingParameter(id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.startupSettings.first { $0.id == id }?.parameter ?? "" },
            // Through the view model, NOT a direct array write: renaming a row must
            // revoke an acknowledgement that was given for the old parameter.
            set: { viewModel.setParameter($0, id: id) }
        )
    }

    private func bindingForSettingType(id: UUID) -> Binding<StartupSettingType> {
        Binding(
            get: { viewModel.startupSettings.first { $0.id == id }?.type ?? .string },
            // The seeding rule lives in `ViewModel.setType` — duplicating it here let the
            // two copies diverge, and the tests were exercising the copy the UI did not use.
            set: { viewModel.setType($0, id: id) }
        )
    }

    private func bindingForSettingValue(id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.startupSettings.first { $0.id == id }?.value ?? "" },
            // Through the view model: editing a sensitive value revokes its
            // acknowledgement (127.0.0.1:9000 approved ≠ 0.0.0.0:9000 approved).
            set: { viewModel.setValue($0, id: id) }
        )
    }

    private func bindingForAcknowledgement(id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.startupSettings.first { $0.id == id }?.isAcknowledged ?? false },
            set: { viewModel.setAcknowledged($0, id: id) }
        )
    }

    private func developerOptionsSection() -> some View {
        Section("Developer Options") {
            Picker("SDK Log Level", selection: $viewModel.logLevel) {
                Text("Error").tag("error")
                Text("Warning").tag("warning")
                Text("Info (Default)").tag("info")
                Text("Debug").tag("debug")
                Text("Verbose").tag("verbose")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("LogLevelPicker")

            Text("Controls DittoLogger.minimumLogLevel when this database is activated. Applied globally across all Ditto instances.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading) {
                Toggle("Enable DQL Strict Mode", isOn: $viewModel.isStrictModeEnabled)
                    .padding(.bottom, 5)
                    .accessibilityIdentifier("StrictModeToggle")

                Text(
                    "⚠️ For most users of Ditto SDK 5.0 and later, strict mode should remain disabled. " +
                        "When disabled, nested objects are treated as MAPs by default, enabling field-level merging. " +
                        "Enable only if you require SDK 4.x compatibility or explicitly need REGISTER-typed objects. " +
                        "Mismatched settings across peers may cause nested fields to appear missing."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            }
        }
    }

    private func secretKeySection() -> some View {
        Section("Optional Secret Key") {
            TextField("Shared Key", text: $viewModel.secretKey)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 5)
                .accessibilityIdentifier("SecretKeyTextField")

            Text("Optional secret key for shared key identity encryption. Leave empty if not using Shared Key.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
        }
    }

    private func serverInformationSection() -> some View {
        // Ditto SDK 5.0 dropped the websocket URL requirement — only the
        // auth URL (now just "URL") is needed.
        Section("Ditto Server (BigPeer) Information") {
            TextField("URL", text: $viewModel.url)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 10)
                .accessibilityIdentifier("UrlTextField")
        }
    }

    private func httpApiSection() -> some View {
        Section("Ditto Server - HTTP API - Optional") {
            TextField("HTTP API URL", text: $viewModel.httpApiUrl)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 8)
                .accessibilityIdentifier("HttpApiUrlTextField")

            TextField("HTTP API Key", text: $viewModel.httpApiKey)
            #if os(macOS)
                .textFieldStyle(.roundedBorder)
            #endif
                .lineLimit(1)
                .padding(.bottom, 10)
                .accessibilityIdentifier("HttpApiKeyTextField")

            VStack(alignment: .leading) {
                Toggle("Allow untrusted certificates", isOn: $viewModel.allowUntrustedCerts)
                    .padding(.bottom, 5)
                    .accessibilityIdentifier("AllowUntrustedCertsToggle")

                Text(
                    "By allowing untrusted certificates, you are bypassing SSL certificate validation entirely, which poses significant security risks. This setting should only be used in development environments and never in production."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            }
        }
    }
}

#Preview {
    DatabaseEditorView(isPresented: .constant(true), dittoAppConfig: DittoConfigForDatabase.new())
}

extension DatabaseEditorView {
    /// Immutable snapshot of every editable field at the time the editor
    /// opened. Used by `hasUnsavedChanges` to detect dirty state without
    /// observing every field individually.
    fileprivate struct OriginalSnapshot: Equatable {
        let name: String
        let databaseId: String
        let developmentToken: String
        let url: String
        let httpApiUrl: String
        let httpApiKey: String
        let mode: AuthMode
        let allowUntrustedCerts: Bool
        let secretKey: String
        let logLevel: String
        let isStrictModeEnabled: Bool
        /// Normalized (trimmed, order-preserving) projections. The row types use a
        /// business key for `Identifiable`, so plain `Equatable` is meaningful here —
        /// no synthetic UUID to exclude.
        let collectionSyncScopes: [CollectionSyncScope]
        let startupSettings: [StartupSetting]
    }

    @MainActor
    @Observable
    class ViewModel {
        let _id: String
        var name: String
        var databaseId: String
        var developmentToken: String
        var url: String
        var httpApiUrl: String
        var httpApiKey: String
        var mode: AuthMode
        var allowUntrustedCerts: Bool
        var secretKey: String
        var logLevel: String
        var isStrictModeEnabled: Bool

        // Transport settings — preserved from existing config, not editable in this view
        var isBluetoothLeEnabled = true
        var isLanEnabled = true
        var isAwdlEnabled = true
        var isCloudSyncEnabled = true
        var isMulticastEnabled = false
        var multicastGroupAddress = MulticastConfig.defaultGroupAddress
        var multicastPort = MulticastConfig.defaultPort
        var multicastInterfaceName: String?

        // MARK: Advanced Configuration

        var collectionSyncScopes: [CollectionSyncScope]
        var startupSettings: [StartupSetting]
        /// Disclosure state, not persisted — collapsed on every open like VS Code.
        ///
        /// Starts expanded under UI tests: the section's own layout is what those tests
        /// assert on, and making them depend on synthesizing a tap turned a real
        /// regression guard into a flaky one.
        var isAdvancedExpanded = isRunningUITests()
        /// Human-readable "name — reason" lines for settings the last open skipped.
        var lastApplyFailures: [String] = []
        /// True when the last open applied scopes it could not verify.
        var lastApplyScopesUnverified = false
        /// True when the stored sync-scope JSON could not be read for this database.
        ///
        /// Save is blocked while this is set and the list is still empty: `save()` builds
        /// a fresh config whose flag defaults to false and writes `"[]"` over the
        /// unreadable JSON, so an unwitting "change the name and Save" cleared the
        /// containment guard and opened the database with no scopes at all — by following
        /// the error message's own advice.
        var hasCorruptSyncScopes = false
        /// Set by the user to accept losing the unreadable scopes.
        var discardCorruptSyncScopes = false

        /// Lists captured by "Reset to SDK Defaults" so the action can be undone.
        @ObservationIgnored private var preResetSyncScopes: [CollectionSyncScope] = []
        @ObservationIgnored private var preResetStartupSettings: [StartupSetting] = []
        /// Set by "Reset to SDK defaults". When the edited database is the one
        /// currently open, saving issues `ALTER SYSTEM RESET ALL` against the live
        /// instance and re-applies everything the app manages.
        var resetToDefaultsRequested = false

        let isNewItem: Bool
        @ObservationIgnored
        private let original: OriginalSnapshot
        private let databaseRepository = DatabaseRepository.shared

        init(_ appConfig: DittoConfigForDatabase) {
            _id = appConfig._id
            name = appConfig.name
            databaseId = appConfig.databaseId
            developmentToken = appConfig.developmentToken
            url = appConfig.url
            httpApiUrl = appConfig.httpApiUrl
            httpApiKey = appConfig.httpApiKey
            mode = appConfig.mode
            allowUntrustedCerts = appConfig.allowUntrustedCerts
            secretKey = appConfig.secretKey
            logLevel = appConfig.logLevel
            isStrictModeEnabled = appConfig.isStrictModeEnabled
            isBluetoothLeEnabled = appConfig.isBluetoothLeEnabled
            isLanEnabled = appConfig.isLanEnabled
            isAwdlEnabled = appConfig.isAwdlEnabled
            isCloudSyncEnabled = appConfig.isCloudSyncEnabled
            isMulticastEnabled = appConfig.isMulticastEnabled
            multicastGroupAddress = appConfig.multicastGroupAddress
            multicastPort = appConfig.multicastPort
            multicastInterfaceName = appConfig.multicastInterfaceName
            collectionSyncScopes = appConfig.collectionSyncScopes
            // Canonicalised on the way in: a stored `.boolean` row spelled `true`/`FALSE`
            // is valid but unrenderable — the value picker tags are exactly
            // `"True"`/`"False"`, so no tag matches and it draws blank.
            let canonicalisedSettings = appConfig.startupSettings.map(Self.canonicalizingBooleanValue)
            startupSettings = canonicalisedSettings
            hasCorruptSyncScopes = appConfig.hasCorruptSyncScopes

            original = OriginalSnapshot(
                name: appConfig.name,
                databaseId: appConfig.databaseId,
                developmentToken: appConfig.developmentToken,
                url: appConfig.url,
                httpApiUrl: appConfig.httpApiUrl,
                httpApiKey: appConfig.httpApiKey,
                mode: appConfig.mode,
                allowUntrustedCerts: appConfig.allowUntrustedCerts,
                secretKey: appConfig.secretKey,
                logLevel: appConfig.logLevel,
                isStrictModeEnabled: appConfig.isStrictModeEnabled,
                // Normalized, to match what `hasUnsavedChanges` compares against:
                // otherwise a stored row with a trailing space reads as an edit on open.
                collectionSyncScopes: Self.normalize(appConfig.collectionSyncScopes),
                // Taken from the **canonicalised** `startupSettings` above, not from
                // `appConfig`: canonicalising `true` → `True` is a representation change the
                // editor applies on load, not a user edit. Snapshotting the raw value made
                // `hasUnsavedChanges` true before the sheet had even been touched, which
                // armed `interactiveDismissDisabled` and a "Discard changes?" prompt for a
                // row nobody edited.
                startupSettings: Self.normalize(canonicalisedSettings)
            )

            if appConfig.databaseId == "" {
                isNewItem = true
            } else {
                isNewItem = false
            }
        }

        /// True when any editable field has diverged from the value the editor
        /// opened with. Drives the discard-changes confirmation dialog and the
        /// host's interactive-dismiss gate. Resets implicitly after a save
        /// because the parent dismisses the sheet.
        var hasUnsavedChanges: Bool {
            name != original.name
                || databaseId != original.databaseId
                || developmentToken != original.developmentToken
                || url != original.url
                || httpApiUrl != original.httpApiUrl
                || httpApiKey != original.httpApiKey
                || mode != original.mode
                || allowUntrustedCerts != original.allowUntrustedCerts
                || secretKey != original.secretKey
                || logLevel != original.logLevel
                || isStrictModeEnabled != original.isStrictModeEnabled
                || normalizedSyncScopes() != original.collectionSyncScopes
                || normalizedStartupSettings() != original.startupSettings
                || resetToDefaultsRequested
        }

        // MARK: - Advanced Configuration

        /// Pulls the outcome of the most recent apply for this database, if it is the
        /// one currently open, so skipped settings are visible in the UI rather than
        /// only in the log file.
        func loadLastApplyOutcome() async {
            guard let active = await DittoManager.shared.dittoSelectedAppConfig,
                  active._id == _id,
                  let result = await DittoManager.shared.lastAdvancedApplyResult else
            {
                lastApplyFailures = []
                lastApplyScopesUnverified = false
                return
            }
            lastApplyFailures = result.skippedSettings.map { "\($0.name) — \($0.reason)" }
            lastApplyScopesUnverified = result.scopesUnverified
        }

        static func normalize(_ scopes: [CollectionSyncScope]) -> [CollectionSyncScope] {
            scopes.compactMap { row in
                let name = row.syncKey
                guard !name.isEmpty else { return nil }
                return CollectionSyncScope(collection: name, scope: row.scope)
            }
        }

        static func normalize(_ settings: [StartupSetting]) -> [StartupSetting] {
            settings.compactMap { row in
                let name = row.syncKey
                guard !name.isEmpty else { return nil }
                return StartupSetting(
                    parameter: name,
                    type: row.type,
                    value: row.value,
                    isAcknowledged: row.isAcknowledged
                )
            }
        }

        /// Trimmed rows, dropping fully-blank ones so a half-typed row doesn't count
        /// as an edit or get persisted.
        func normalizedSyncScopes() -> [CollectionSyncScope] {
            Self.normalize(collectionSyncScopes)
        }

        func normalizedStartupSettings() -> [StartupSetting] {
            Self.normalize(startupSettings)
        }

        /// Validation error for a scope row, if any.
        func syncScopeError(id: UUID) -> AdvancedSettingsValidator.CollectionError? {
            guard let index = collectionSyncScopes.firstIndex(where: { $0.id == id }) else { return nil }
            let others = collectionSyncScopes.filter { $0.id != id }.map(\.collection)
            return AdvancedSettingsValidator.validateCollection(
                collectionSyncScopes[index].collection,
                others: others
            )
        }

        /// Validation error for a startup-setting row, if any.
        func startupSettingError(id: UUID) -> AdvancedSettingsValidator.ParameterError? {
            guard let index = startupSettings.firstIndex(where: { $0.id == id }) else { return nil }
            let others = startupSettings.filter { $0.id != id }.map(\.parameter)
            return AdvancedSettingsValidator.validateSetting(startupSettings[index], others: others)
        }

        /// True when the row is risky, whether or not it has been acknowledged — the
        /// Toggle stays visible once ticked so the user can withdraw it.
        func isSensitiveRow(id: UUID) -> Bool {
            guard let setting = startupSettings.first(where: { $0.id == id }) else { return false }
            let name = setting.syncKey
            return !name.isEmpty && AdvancedSettingsValidator.isSensitiveParameter(name)
        }

        /// Acknowledgement is stored ON the row (and persisted), so it survives a
        /// rename-free round trip and, critically, is re-checked on the apply path for
        /// settings that never passed through this editor.
        func setAcknowledged(_ acknowledged: Bool, id: UUID) {
            guard let index = startupSettings.firstIndex(where: { $0.id == id }) else { return }
            startupSettings[index].isAcknowledged = acknowledged
        }

        /// Renaming revokes the acknowledgement: it approved a specific parameter, so
        /// turning `foo_port` into `additional_p2p_trusted_ca_certs` must re-prompt.
        func setParameter(_ newValue: String, id: UUID) {
            guard let index = startupSettings.firstIndex(where: { $0.id == id }) else { return }
            let previous = startupSettings[index].syncKey.lowercased()
            startupSettings[index].parameter = newValue
            if startupSettings[index].syncKey.lowercased() != previous {
                startupSettings[index].isAcknowledged = false
            }
        }

        /// Editing the value revokes it too — approving `127.0.0.1:9000` is not approval
        /// for `0.0.0.0:9000`, which listens on every interface.
        func setValue(_ newValue: String, id: UUID) {
            guard let index = startupSettings.firstIndex(where: { $0.id == id }) else { return }
            guard startupSettings[index].value != newValue else { return }
            startupSettings[index].value = newValue
            if AdvancedSettingsValidator.isSensitiveParameter(startupSettings[index].syncKey) {
                startupSettings[index].isAcknowledged = false
            }
        }

        /// Changes a row's type, seeding a valid default when switching to Boolean but
        /// never clearing a typed value otherwise — silently discarding a pasted blob
        /// because the picker was brushed has no undo.
        func setType(_ newValue: StartupSettingType, id: UUID) {
            guard let index = startupSettings.firstIndex(where: { $0.id == id }) else { return }
            let previous = startupSettings[index].type
            guard previous != newValue else { return }
            startupSettings[index].type = newValue

            guard newValue == .boolean else { return }

            // A boolean row's value must be one of the picker's exact tags. An existing
            // boolean is kept — only its spelling is canonicalised, because `true` and
            // `True` mean the same thing to `typedValue` but only one of them renders.
            let current = startupSettings[index].value
            let canonical = StartupSetting.canonicalBooleanValue(current)
            let seeded = canonical ?? "True"
            guard seeded != current else { return }
            startupSettings[index].value = seeded

            // Seeding — as opposed to re-spelling — is a real value change, and an
            // acknowledgement approved a (name, value) pair: `sqlite3_synchronous = FULL`
            // approved is not `= true` approved. Only `setValue` used to revoke, so
            // switching the type past a sensitive row applied a durability or exposure
            // setting at a value nobody agreed to, with no re-prompt. Mirrors `setValue`
            // deliberately; the two must not diverge.
            //
            // Canonicalising `true` → `True` is NOT a value change (`typedValue` lowercases
            // before matching, so both mean the same thing) and must not force a needless
            // re-tick, which is why this is gated on `canonical == nil`.
            if canonical == nil,
               AdvancedSettingsValidator.isSensitiveParameter(startupSettings[index].syncKey)
            {
                startupSettings[index].isAcknowledged = false
            }
        }

        /// Returns `setting` with a `.boolean` value spelled the way the picker tags it.
        /// Non-boolean rows and unrecognised text are returned untouched — silently
        /// rewriting a value the user typed is exactly what `setType` refuses to do.
        private static func canonicalizingBooleanValue(_ setting: StartupSetting) -> StartupSetting {
            guard setting.type == .boolean,
                  let canonical = StartupSetting.canonicalBooleanValue(setting.value),
                  canonical != setting.value else
            {
                return setting
            }
            var canonicalised = setting
            canonicalised.value = canonical
            return canonicalised
        }

        /// Blocks Save while any advanced row is invalid or unacknowledged.
        /// True while the unreadable scopes have neither been replaced nor explicitly
        /// discarded.
        var blocksSaveForCorruptScopes: Bool {
            hasCorruptSyncScopes && collectionSyncScopes.isEmpty && !discardCorruptSyncScopes
        }

        var hasAdvancedValidationErrors: Bool {
            if blocksSaveForCorruptScopes {
                return true
            }
            if collectionSyncScopes.contains(where: { syncScopeError(id: $0.id) != nil }) {
                return true
            }
            if startupSettings.contains(where: { startupSettingError(id: $0.id) != nil }) {
                return true
            }

            if collectionSyncScopes.count > AdvancedSettingsValidator.maxRowCount {
                return true
            }
            if startupSettings.count > AdvancedSettingsValidator.maxRowCount {
                return true
            }
            return false
        }

        /// Summary shown in the disclosure header, mirroring the VS Code extension.
        var advancedSummary: String {
            let scopes = collectionSyncScopes.count
            let settings = startupSettings.count
            let scopeText = scopes == 1 ? "1 scope" : "\(scopes) scopes"
            let settingText = settings == 1 ? "1 startup setting" : "\(settings) startup settings"
            return "\(scopeText) · \(settingText)"
        }

        func addSyncScope() {
            collectionSyncScopes.append(CollectionSyncScope(collection: "", scope: .allPeers))
        }

        func removeSyncScope(id: UUID) {
            collectionSyncScopes.removeAll { $0.id == id } // id is a UUID: exactly one row
        }

        func addStartupSetting() {
            startupSettings.append(StartupSetting(parameter: "", type: .string, value: ""))
        }

        func removeStartupSetting(id: UUID) {
            startupSettings.removeAll { $0.id == id } // id is a UUID: exactly one row
        }

        /// Clears both lists and marks the config so a live instance is reset to SDK
        /// defaults on save. On a database that isn't open there is nothing to reset —
        /// `ALTER SYSTEM` state dies with the instance, so the next open is already
        /// at defaults.
        func resetAdvancedToDefaults() {
            // Snapshot so the user can back out — this used to be a one-way flag that
            // wiped both lists with no undo and left the form permanently dirty.
            //
            // Only on the FIRST reset: the button reappears once the user re-enters a
            // row, and re-snapshotting there replaced the original lists with that one
            // new row, losing the real data with no undo.
            if !resetToDefaultsRequested {
                preResetSyncScopes = collectionSyncScopes
                preResetStartupSettings = startupSettings
            }
            collectionSyncScopes.removeAll()
            startupSettings.removeAll()
            resetToDefaultsRequested = true
        }

        /// True while Undo Reset is safe to offer — once the user has started re-entering
        /// rows, restoring the snapshot would silently discard that work.
        var canUndoResetToDefaults: Bool {
            resetToDefaultsRequested && collectionSyncScopes.isEmpty && startupSettings.isEmpty
        }

        /// Restores the lists the reset cleared and cancels the pending `RESET ALL`.
        func undoResetToDefaults() {
            guard canUndoResetToDefaults else { return }
            collectionSyncScopes = preResetSyncScopes
            startupSettings = preResetStartupSettings
            preResetSyncScopes = []
            preResetStartupSettings = []
            resetToDefaultsRequested = false
        }

        @discardableResult
        func save(appState: AppState) async -> Bool {
            do {
                // New registrations trim; existing ones keep the stored value verbatim.
                //
                // `updateDatabaseConfig` no longer writes the `databaseId` column at all
                // (it is a foreign key with no `ON UPDATE`, and it names the on-disk store
                // directory). So trimming here for an existing config would put a trimmed
                // value in the in-memory cache and in `refreshSelectedConfigIfMatching`
                // while the untrimmed value stayed on disk — a silent divergence for any
                // legacy row that has surrounding whitespace. The field is also disabled
                // in the UI for existing configs, so this cannot differ in practice; it
                // is written explicitly so the invariant survives a future edit that
                // re-enables the field.
                let persistedDatabaseId = isNewItem
                    ? databaseId.trimmingCharacters(in: .whitespacesAndNewlines)
                    : original.databaseId

                let appConfig = DittoConfigForDatabase(
                    _id,
                    name: name,
                    databaseId: persistedDatabaseId,
                    developmentToken: developmentToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    url: url,
                    httpApiUrl: httpApiUrl,
                    httpApiKey: httpApiKey,
                    mode: mode,
                    allowUntrustedCerts: allowUntrustedCerts,
                    secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    isBluetoothLeEnabled: isBluetoothLeEnabled,
                    isLanEnabled: isLanEnabled,
                    isAwdlEnabled: isAwdlEnabled,
                    isCloudSyncEnabled: isCloudSyncEnabled,
                    isMulticastEnabled: isMulticastEnabled,
                    multicastGroupAddress: multicastGroupAddress,
                    multicastPort: multicastPort,
                    multicastInterfaceName: multicastInterfaceName,
                    logLevel: logLevel,
                    isStrictModeEnabled: isStrictModeEnabled,
                    collectionSyncScopes: normalizedSyncScopes(),
                    startupSettings: normalizedStartupSettings()
                )
                if isNewItem {
                    try await databaseRepository.addDittoAppConfig(appConfig)
                } else {
                    try await databaseRepository.updateDittoAppConfig(appConfig)

                    // Keep the actor's copy of the active config current, or a later
                    // sync restart would re-apply the settings this database was opened
                    // with — silently reverting the scope the user just changed.
                    await DittoManager.shared.refreshSelectedConfigIfMatching(appConfig)

                    // "Reset to SDK defaults" only has an observable effect on a live
                    // instance; for a closed database the next open already starts at
                    // defaults. Surfaced rather than swallowed: a failed RESET ALL means
                    // the saved config says "defaults" while the running instance still
                    // has the old parameters — including transports the user disabled.
                    if resetToDefaultsRequested {
                        do {
                            try await DittoManager.shared.resetSystemSettingsToDefaults(for: appConfig)
                        } catch {
                            Log.error("Could not reset system settings: \(error.localizedDescription)")
                            appState.setError(AppError.error(
                                message: "Settings were saved, but restoring Ditto's defaults on the " +
                                    "running database failed: \(error.localizedDescription) " +
                                    "Close and reopen the database to apply them."
                            ))
                        }
                    }
                    // The config (incl. logLevel) is already saved above. Applying
                    // the live SDK log level is best-effort and must NOT fail the
                    // save or trigger the error alert + sheet dismissal — it takes
                    // effect on next open if it throws here.
                    do {
                        try await DittoManager.shared.changeDittoLogLevel(logLevel, for: appConfig)
                    } catch {
                        Log.warning("Could not apply log level immediately: \(error.localizedDescription)")
                    }
                }
                // The write committed, so the pending reset is no longer pending.
                resetToDefaultsRequested = false
                return true
            } catch {
                appState.setError(error)
                return false
            }
        }
    }
}

/// View modifier to handle paste trimming
struct PasteTrimModifier: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .onPasteCommand(of: [.plainText]) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                        if let string = string as? String {
                            Task { @MainActor in
                                text = string.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                }
            }
        #else
        content
        #endif
    }
}

extension View {
    func trimOnPaste(_ text: Binding<String>) -> some View {
        modifier(PasteTrimModifier(text: text))
    }
}
