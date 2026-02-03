import SwiftUI
import UniformTypeIdentifiers

struct ImportDataView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String = "No file selected"
    @State private var collectionName: String = ""
    @State private var useExistingCollection: Bool = true
    @State private var existingCollections: [DittoCollection] = []
    @State private var selectedCollection: String = ""
    @State private var isImporting: Bool = false
    @State private var showingFilePicker: Bool = false
    @State private var importProgress: ImportService.ImportProgress?
    @State private var currentImportStatus: String = ""
    @State private var importError: String? = nil
    @State private var importSuccess: Bool = false
    @State private var successMessage: String = ""
    @State private var useInitialInsert: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Import JSON Data")
                .font(.title2)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)
            
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select JSON File")
                        .font(.headline)
                    
                    HStack {
                        Text(selectedFileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(selectedFileURL == nil ? .secondary : .primary)
                        
                        Spacer()
                        
                        Button("Choose File...") {
                            showingFilePicker = true
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Target Collection")
                        .font(.headline)
                    
                    Picker("", selection: $useExistingCollection) {
                        Text("Existing Collection").tag(true)
                        Text("New Collection").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    if useExistingCollection {
                        if existingCollections.isEmpty {
                            Text("No existing collections found")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack {
                                Text("Select Collection")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Picker("", selection: $selectedCollection) {
                                    ForEach(existingCollections, id: \._id) { collection in
                                        Text(collection.name).tag(collection.name)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                    } else {
                        TextField("New collection name", text: $collectionName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Insert Type")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Toggle(isOn: $useInitialInsert) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(useInitialInsert ? "Initial Documents Insert" : "Regular Insert")
                                    .font(.system(size: 13))
                                Text(useInitialInsert ? 
                                     "Use for first-time data import (WITH INITIAL DOCUMENTS)" : 
                                     "Use for adding data to existing collections")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    
                    if useInitialInsert {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Initial insert is designed for loading data for the first time and has special optimizations.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
            }
            
            // Add more spacing before Status section
            if isImporting || importError != nil || importSuccess {
                Spacer()
                    .frame(height: 20)
            }
            
            // Status Section
            if isImporting || importError != nil || importSuccess {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status")
                        .font(.headline)
                    
                    if isImporting {
                        VStack(alignment: .leading, spacing: 10) {
                            if let progress = importProgress {
                                // Progress bar
                                ProgressView(value: Double(progress.current), total: Double(progress.total))
                                    .progressViewStyle(.linear)
                                
                                HStack {
                                    Text("Importing: \(progress.current) of \(progress.total) documents")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                
                                if let docId = progress.currentDocumentId {
                                    Text("Processing: \(docId)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            } else {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                    Text(currentImportStatus.isEmpty ? "Preparing import..." : currentImportStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                    } else if let error = importError {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 14))
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.1))
                        )
                    } else if importSuccess {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                            Text(successMessage)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green.opacity(0.1))
                        )
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: isImporting)
                .animation(.easeInOut(duration: 0.3), value: importError)
                .animation(.easeInOut(duration: 0.3), value: importSuccess)
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                if importSuccess {
                    Button("Done") {
                        isPresented = false
                    }
                    .keyboardShortcut(.return)
                } else {
                    Button("Import") {
                        performImport()
                    }
                    .keyboardShortcut(.return)
                    .disabled(!canImport || isImporting)
                }
            }
        }
        .padding(30)
        .frame(width: 550)
        .frame(minHeight: 500, maxHeight: 600)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let files):
                if let file = files.first {
                    // Store the security-scoped URL
                    selectedFileURL = file
                    selectedFileName = file.lastPathComponent
                }
            case .failure(let error):
                appState.setError(error)
            }
        }
        .onAppear {
            loadExistingCollections()
        }
    }
    
    private var canImport: Bool {
        guard selectedFileURL != nil else { return false }
        
        if useExistingCollection {
            return !selectedCollection.isEmpty
        } else {
            return !collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private func loadExistingCollections() {
        Task {
            do {
                existingCollections = try await CollectionsRepository.shared.hydrateCollections()
                if !existingCollections.isEmpty {
                    selectedCollection = existingCollections[0].name
                }
            } catch {
                appState.setError(error)
            }
        }
    }
    
    private func performImport() {
        guard let fileURL = selectedFileURL else { return }
        
        let targetCollection = useExistingCollection ? selectedCollection : collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !targetCollection.isEmpty else {
            importError = "Collection name cannot be empty"
            return
        }
        
        // Clear any previous state
        importError = nil
        importSuccess = false
        successMessage = ""
        
        isImporting = true
        importProgress = nil
        currentImportStatus = "Reading file..."
        
        Task {
            do {
                // Update status before starting
                await MainActor.run {
                    currentImportStatus = "Validating JSON data..."
                }
                
                // Small delay to show the status
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 second
                
                await MainActor.run {
                    currentImportStatus = "Starting import to \(targetCollection)..."
                }
                
                let result = try await ImportService.shared.importData(
                    from: fileURL,
                    to: targetCollection,
                    insertType: useInitialInsert ? .initial : .regular
                ) { progress in
                    Task { @MainActor in
                        self.importProgress = progress
                    }
                }
                
                await MainActor.run {
                    isImporting = false
                    importProgress = nil
                    currentImportStatus = ""
                    
                    if result.failureCount == 0 {
                        importSuccess = true
                        successMessage = "Successfully imported \(result.successCount) document(s) to \(targetCollection)"
                    } else {
                        importSuccess = true
                        successMessage = "Imported \(result.successCount) document(s) with \(result.failureCount) failure(s)"
                        if !result.errors.isEmpty {
                            // Show first error
                            importError = result.errors.first
                        }
                    }
                    
                    // Refresh collections if we created a new one
                    if !useExistingCollection {
                        loadExistingCollections()
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importProgress = nil
                    currentImportStatus = ""
                    importError = error.localizedDescription
                }
            }
        }
    }
}