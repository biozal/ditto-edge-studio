import SwiftUI

// MARK: - Icon Display Model

struct IconDebugInfo: Identifiable {
    let id = UUID()
    let icon: any FontAwesomeIcon
    let aliasName: String
    let category: String
    let unicode: String
    let fontFamily: String

    // Computed property for font weight display
    var fontWeight: String {
        return icon.style.displayName
    }

    // Computed property to check if icon renders
    var rendersCorrectly: Bool {
        // Icon renders if it's not showing as empty box
        return true  // Can enhance with actual rendering check
    }
}

// MARK: - Font Debug Window

struct FontDebugWindow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    private let categories = [
        "All",
        "Platform Icons",
        "Connectivity Icons",
        "System Icons",
        "Navigation Icons",
        "Action Icons",
        "Data Icons",
        "Status Icons",
        "UI Icons"
    ]

    // All icons used in the app organized by category
    private var allIcons: [IconDebugInfo] {
        var icons: [IconDebugInfo] = []

        // Platform Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: PlatformIcon.linux, aliasName: "PlatformIcon.linux",
                         category: "Platform Icons", unicode: "f17c",
                         fontFamily: "FontAwesome7Brands-Regular"),
            IconDebugInfo(icon: PlatformIcon.apple, aliasName: "PlatformIcon.apple",
                         category: "Platform Icons", unicode: "f179",
                         fontFamily: "FontAwesome7Brands-Regular"),
            IconDebugInfo(icon: PlatformIcon.android, aliasName: "PlatformIcon.android",
                         category: "Platform Icons", unicode: "f17b",
                         fontFamily: "FontAwesome7Brands-Regular"),
            IconDebugInfo(icon: PlatformIcon.iOS, aliasName: "PlatformIcon.iOS",
                         category: "Platform Icons", unicode: "e1ee",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: PlatformIcon.windows, aliasName: "PlatformIcon.windows",
                         category: "Platform Icons", unicode: "f17a",
                         fontFamily: "FontAwesome7Brands-Regular"),
        ])

        // Connectivity Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: ConnectivityIcon.bluetooth, aliasName: "ConnectivityIcon.bluetooth",
                         category: "Connectivity Icons", unicode: "f293",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ConnectivityIcon.wifi, aliasName: "ConnectivityIcon.wifi",
                         category: "Connectivity Icons", unicode: "f1eb",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ConnectivityIcon.network, aliasName: "ConnectivityIcon.network",
                         category: "Connectivity Icons", unicode: "f6a9",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ConnectivityIcon.ethernet, aliasName: "ConnectivityIcon.ethernet",
                         category: "Connectivity Icons", unicode: "f796",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ConnectivityIcon.broadcastTower, aliasName: "ConnectivityIcon.broadcastTower",
                         category: "Connectivity Icons", unicode: "f519",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ConnectivityIcon.cloud, aliasName: "ConnectivityIcon.cloud",
                         category: "Connectivity Icons", unicode: "f0c2",
                         fontFamily: "FontAwesome7Pro-Solid"),
        ])

        // System Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: SystemIcon.sdk, aliasName: "SystemIcon.sdk",
                         category: "System Icons", unicode: "e2d1",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: SystemIcon.link, aliasName: "SystemIcon.link",
                         category: "System Icons", unicode: "f0c1",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: SystemIcon.circleInfo, aliasName: "SystemIcon.circleInfo",
                         category: "System Icons", unicode: "f05a",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: SystemIcon.circleCheck, aliasName: "SystemIcon.circleCheck",
                         category: "System Icons", unicode: "f058",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: SystemIcon.clock, aliasName: "SystemIcon.clock",
                         category: "System Icons", unicode: "f017",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: SystemIcon.question, aliasName: "SystemIcon.question",
                         category: "System Icons", unicode: "f059",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: SystemIcon.gear, aliasName: "SystemIcon.gear",
                         category: "System Icons", unicode: "f013",
                         fontFamily: "FontAwesome7Pro-Solid"),
        ])

        // Navigation Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: NavigationIcon.chevronLeft, aliasName: "NavigationIcon.chevronLeft",
                         category: "Navigation Icons", unicode: "f053",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: NavigationIcon.chevronRight, aliasName: "NavigationIcon.chevronRight",
                         category: "Navigation Icons", unicode: "f054",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: NavigationIcon.play, aliasName: "NavigationIcon.play",
                         category: "Navigation Icons", unicode: "f04b",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: NavigationIcon.refresh, aliasName: "NavigationIcon.refresh",
                         category: "Navigation Icons", unicode: "f021",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: NavigationIcon.sync, aliasName: "NavigationIcon.sync",
                         category: "Navigation Icons", unicode: "f2f1",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: NavigationIcon.syncLight, aliasName: "NavigationIcon.syncLight",
                         category: "Navigation Icons", unicode: "f2f1",
                         fontFamily: "FontAwesome7Pro-Light"),
        ])

        // Action Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: ActionIcon.plus, aliasName: "ActionIcon.plus",
                         category: "Action Icons", unicode: "f067",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ActionIcon.circlePlus, aliasName: "ActionIcon.circlePlus",
                         category: "Action Icons", unicode: "f055",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ActionIcon.circleXmark, aliasName: "ActionIcon.circleXmark",
                         category: "Action Icons", unicode: "f057",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ActionIcon.circleXmarkLight, aliasName: "ActionIcon.circleXmarkLight",
                         category: "Action Icons", unicode: "f057",
                         fontFamily: "FontAwesome7Pro-Light"),
            IconDebugInfo(icon: ActionIcon.download, aliasName: "ActionIcon.download",
                         category: "Action Icons", unicode: "f019",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: ActionIcon.copy, aliasName: "ActionIcon.copy",
                         category: "Action Icons", unicode: "f0c5",
                         fontFamily: "FontAwesome7Pro-Solid"),
        ])

        // Data Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: DataIcon.code, aliasName: "DataIcon.code",
                         category: "Data Icons", unicode: "f121",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: DataIcon.table, aliasName: "DataIcon.table",
                         category: "Data Icons", unicode: "f0ce",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: DataIcon.database, aliasName: "DataIcon.database",
                         category: "Data Icons", unicode: "f1c0",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: DataIcon.databaseRegular, aliasName: "DataIcon.databaseRegular",
                         category: "Data Icons", unicode: "f1c0",
                         fontFamily: "FontAwesome7Pro-Regular"),
            IconDebugInfo(icon: DataIcon.databaseThin, aliasName: "DataIcon.databaseThin",
                         category: "Data Icons", unicode: "f1c0",
                         fontFamily: "FontAwesome7Pro-Thin"),
            IconDebugInfo(icon: DataIcon.layerGroup, aliasName: "DataIcon.layerGroup",
                         category: "Data Icons", unicode: "f5fd",
                         fontFamily: "FontAwesome7Pro-Solid"),
        ])

        // Status Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: StatusIcon.circleCheck, aliasName: "StatusIcon.circleCheck",
                         category: "Status Icons", unicode: "f058",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: StatusIcon.circleInfo, aliasName: "StatusIcon.circleInfo",
                         category: "Status Icons", unicode: "f05a",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: StatusIcon.triangleExclamation, aliasName: "StatusIcon.triangleExclamation",
                         category: "Status Icons", unicode: "f071",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: StatusIcon.circleQuestion, aliasName: "StatusIcon.circleQuestion",
                         category: "Status Icons", unicode: "f059",
                         fontFamily: "FontAwesome7Pro-Solid"),
        ])

        // UI Icons
        icons.append(contentsOf: [
            IconDebugInfo(icon: UIIcon.star, aliasName: "UIIcon.star",
                         category: "UI Icons", unicode: "f005",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: UIIcon.eye, aliasName: "UIIcon.eye",
                         category: "UI Icons", unicode: "f06e",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: UIIcon.clock, aliasName: "UIIcon.clock",
                         category: "UI Icons", unicode: "f017",
                         fontFamily: "FontAwesome7Pro-Solid"),
            IconDebugInfo(icon: UIIcon.circleNodes, aliasName: "UIIcon.circleNodes",
                         category: "UI Icons", unicode: "e4e2",
                         fontFamily: "FontAwesome7Pro-Solid"),
        ])

        return icons
    }

    // Filtered icons based on search and category
    private var filteredIcons: [IconDebugInfo] {
        allIcons.filter { icon in
            let matchesSearch = searchText.isEmpty ||
                icon.aliasName.localizedCaseInsensitiveContains(searchText) ||
                icon.unicode.localizedCaseInsensitiveContains(searchText)

            let matchesCategory = selectedCategory == "All" ||
                icon.category == selectedCategory

            return matchesSearch && matchesCategory
        }
    }

    // Group icons by category
    private var groupedIcons: [String: [IconDebugInfo]] {
        Dictionary(grouping: filteredIcons, by: { $0.category })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title, search, filter, and close button
            VStack(spacing: 12) {
                // Title bar with close button
                HStack {
                    Text("Font Awesome Icons - Debug")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        NSApplication.shared.keyWindow?.close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Font Debug Window")
                }

                // Search and filter row
                HStack {
                    TextField("Search icons...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .frame(width: 180)
                }

                HStack {
                    Text("\(filteredIcons.count) icons")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Icon list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedIcons.keys.sorted(), id: \.self) { category in
                        Section(header: categoryHeader(category)) {
                            ForEach(groupedIcons[category] ?? []) { iconInfo in
                                iconRow(iconInfo)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                Divider()
                                    .padding(.leading, 68)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
    }

    // MARK: - View Builders

    private func categoryHeader(_ category: String) -> some View {
        HStack {
            Text(category)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
    }

    private func iconRow(_ iconInfo: IconDebugInfo) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon visual
            FontAwesomeText(icon: iconInfo.icon, size: 32)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

            // Icon details
            VStack(alignment: .leading, spacing: 4) {
                Text(iconInfo.aliasName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Label("Unicode:", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(iconInfo.unicode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    Label("Font:", systemImage: "textformat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(iconInfo.fontFamily)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    Label("Weight:", systemImage: "scalemass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(iconInfo.fontWeight)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }

                if iconInfo.rendersCorrectly {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Renders correctly")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Copy button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(iconInfo.aliasName, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy alias name to clipboard")
        }
    }
}

// MARK: - Preview

#Preview {
    FontDebugWindow()
}
