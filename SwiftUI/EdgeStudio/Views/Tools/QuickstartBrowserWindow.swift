import SwiftUI

// MARK: - QuickstartBrowserWindow

/// Window that displays downloaded quickstart projects with copyable paths.
struct QuickstartBrowserWindow: View {
    @Environment(\.dismiss) private var dismiss

    let projects: [QuickstartProject]
    let isConfigured: Bool
    let quickstartDir: URL

    @State private var copiedProjectId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if !isConfigured {
                warningBanner
            }

            Divider()

            projectList
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ditto Quickstart Projects")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(quickstartDir.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text("Projects not auto-configured — connect to a database and re-download to auto-configure, or create .env manually from .env.sample")
                .font(.callout)

            Spacer()
        }
        .padding(12)
        .background(.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Project List

    private var projectList: some View {
        List(projects) { project in
            QuickstartProjectRow(
                project: project,
                isCopied: copiedProjectId == project.id,
                onCopy: {
                    copyPath(project.path.path, projectId: project.id)
                }
            )
        }
        #if os(macOS)
        .listStyle(.inset(alternatesRowBackgrounds: true))
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Copy to Clipboard

    private func copyPath(_ path: String, projectId: UUID) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        #else
        UIPasteboard.general.string = path
        #endif

        copiedProjectId = projectId

        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if copiedProjectId == projectId {
                    copiedProjectId = nil
                }
            }
        }
    }
}

// MARK: - QuickstartProjectRow

/// A single row in the quickstart browser list showing project name, path, and a copy button.
struct QuickstartProjectRow: View {
    let project: QuickstartProject
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Configured status indicator
            Image(systemName: project.isConfigured ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(project.isConfigured ? .green : .secondary)

            // Project name and path
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)

                Text(project.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            // Copy path button
            Button {
                onCopy()
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .primary)
            }
            .buttonStyle(.borderless)
            .help("Copy path to clipboard")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Configured") {
    let dir = URL(fileURLWithPath: "/Users/example/quickstart-main")
    let projects: [QuickstartProject] = [
        QuickstartProject(name: "Swift", directoryName: "swift", path: dir.appendingPathComponent("swift"), isConfigured: true),
        QuickstartProject(
            name: "Android Kotlin",
            directoryName: "android-kotlin",
            path: dir.appendingPathComponent("android-kotlin"),
            isConfigured: true
        ),
        QuickstartProject(name: "React Native", directoryName: "react-native", path: dir.appendingPathComponent("react-native"), isConfigured: false)
    ]
    return QuickstartBrowserWindow(projects: projects, isConfigured: true, quickstartDir: dir)
}

#Preview("Not Configured") {
    let dir = URL(fileURLWithPath: "/Users/example/quickstart-main")
    let projects: [QuickstartProject] = [
        QuickstartProject(name: "Swift", directoryName: "swift", path: dir.appendingPathComponent("swift"), isConfigured: false),
        QuickstartProject(name: "Flutter", directoryName: "flutter_app", path: dir.appendingPathComponent("flutter_app"), isConfigured: false)
    ]
    return QuickstartBrowserWindow(projects: projects, isConfigured: false, quickstartDir: dir)
}
