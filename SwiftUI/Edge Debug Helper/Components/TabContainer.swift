//
//  TabContainer.swift
//  Edge Studio
//
//  Created on today's date.
//

import SwiftUI

struct TabContainer: View {
  @Binding var openTabs: [TabItem]
  @Binding var activeTabId: UUID?
  let onCloseTab: (TabItem) -> Void
  let onSelectTab: (TabItem) -> Void
  let contentForTab: (TabItem) -> AnyView
  let defaultContent: () -> AnyView
  var titleForTab: ((TabItem) -> String)? // Optional function to get dynamic titles

  var body: some View {
    VStack(spacing: 0) {
      if openTabs.isEmpty {
        // No tabs - show default content
        defaultContent()
      } else {
        // Tab Bar with navigation controls
        HStack(spacing: 0) {
          // Tab navigation controls (like Xcode)
          HStack(spacing: 2) {
            // Previous tab button with proper hit area
            Button(action: navigateToPreviousTab) {
              Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(canNavigateToPrevious ? Color.primary : Color.secondary.opacity(0.3))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle()) // Make entire area clickable
            }
            .buttonStyle(.plain)
            .disabled(!canNavigateToPrevious)

            // Next tab button with proper hit area
            Button(action: navigateToNextTab) {
              Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(canNavigateToNext ? Color.primary : Color.secondary.opacity(0.3))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle()) // Make entire area clickable
            }
            .buttonStyle(.plain)
            .disabled(!canNavigateToNext)
          }
          .padding(.leading, 4)

          Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)

          // Tab items
          HStack(spacing: 2) {
            ForEach(openTabs) { tab in
              TabComponent(
                tab: tab,
                isActive: activeTabId == tab.id,
                onSelect: { onSelectTab(tab) },
                onClose: { onCloseTab(tab) },
                displayTitle: titleForTab?(tab)
              )
            }
          }
          .padding(.trailing, 8)
          .padding(.vertical, 4)

          Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .frame(height: 36)

        // Tab Content
        VStack(spacing: 0) {
          if let activeTabId = activeTabId,
            let activeTab = openTabs.first(where: { $0.id == activeTabId })
          {
            contentForTab(activeTab)
          } else {
            defaultContent()
          }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - Navigation helpers
  private var canNavigateToPrevious: Bool {
    guard let activeTabId = activeTabId,
          let currentIndex = openTabs.firstIndex(where: { $0.id == activeTabId }) else {
      return false
    }
    return currentIndex > 0
  }

  private var canNavigateToNext: Bool {
    guard let activeTabId = activeTabId,
          let currentIndex = openTabs.firstIndex(where: { $0.id == activeTabId }) else {
      return false
    }
    return currentIndex < openTabs.count - 1
  }

  private func navigateToPreviousTab() {
    guard let activeTabId = activeTabId,
          let currentIndex = openTabs.firstIndex(where: { $0.id == activeTabId }),
          currentIndex > 0 else {
      return
    }
    let previousTab = openTabs[currentIndex - 1]
    onSelectTab(previousTab)
  }

  private func navigateToNextTab() {
    guard let activeTabId = activeTabId,
          let currentIndex = openTabs.firstIndex(where: { $0.id == activeTabId }),
          currentIndex < openTabs.count - 1 else {
      return
    }
    let nextTab = openTabs[currentIndex + 1]
    onSelectTab(nextTab)
  }
}

// MARK: - Individual Tab Component
struct TabComponent: View {
  let tab: TabItem
  let isActive: Bool
  let onSelect: () -> Void
  let onClose: () -> Void
  let displayTitle: String? // Optional override for dynamic titles
  @State private var isHoveringTab = false
  @State private var isHoveringClose = false

  var body: some View {
    ZStack {
      Rectangle()
        .fill(backgroundColor)
        .allowsHitTesting(false)  // background is visual only

      HStack(spacing: 8) {
        // Tab select button
        Button(action: {
          onSelect()
        }) {
          HStack(spacing: 6) {
            Image(systemName: tab.systemImage)
              .font(.system(size: 12))
            Text(displayTitle ?? tab.title)
              .font(.system(size: 13))
              .lineLimit(1)
          }
          .contentShape(Rectangle())  // clickable area
        }
        .buttonStyle(.plain)

        // Close button
        Button(action: {
          onClose()
        }) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isHoveringClose ? .white : .secondary)
            .frame(width: 16, height: 16)
            .background(
              Circle()
                .fill(isHoveringClose ? Color.red.opacity(0.8) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          withAnimation(.easeInOut(duration: 0.15)) {
            isHoveringClose = hovering
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)

      if isHoveringTab && !isActive {
        RoundedRectangle(cornerRadius: 4)
          .strokeBorder(Color.accentColor, lineWidth: 1.5)
          .padding(2)
      }
    }
    .fixedSize(horizontal: true, vertical: false)  // Size to content width
    .contentShape(Rectangle())  // defines a clear hit-test area
    .allowsHitTesting(true)  // make sure the root accepts events
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.1)) {
        isHoveringTab = hovering
      }
    }
  }

  private var backgroundColor: Color {
    if isActive {
      return Color.accentColor.opacity(0.15)
    } else {
      return Color.clear
    }
  }
}
