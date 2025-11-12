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
  var onNewQuery: (() -> Void)? // Optional callback for new query button

  var body: some View {
    VStack(spacing: 0) {
      // Tab Bar - always show (with or without tabs)
      HStack(spacing: 0) {
        // Tab navigation controls (always visible) - Fixed position
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

        // Scrollable tab items area (only show if tabs exist)
        if !openTabs.isEmpty {
          #if os(macOS)
          MacOSHorizontalScroller(activeTabId: activeTabId) {
            HStack(spacing: 2) {
              ForEach(openTabs) { tab in
                TabComponent(
                  tab: tab,
                  isActive: activeTabId == tab.id,
                  onSelect: { onSelectTab(tab) },
                  onClose: { onCloseTab(tab) },
                  displayTitle: titleForTab?(tab)
                )
                .id(tab.id)
              }
            }
            .padding(.vertical, 4)
          }
          .frame(maxWidth: .infinity) // Allow scroller to take available space
          #else
          ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 2) {
                ForEach(openTabs) { tab in
                  TabComponent(
                    tab: tab,
                    isActive: activeTabId == tab.id,
                    onSelect: { onSelectTab(tab) },
                    onClose: { onCloseTab(tab) },
                    displayTitle: titleForTab?(tab)
                  )
                  .id(tab.id)
                }
              }
              .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity) // Allow scroll view to take available space
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: activeTabId) { _, newTabId in
              if let newTabId = newTabId {
                withAnimation {
                  proxy.scrollTo(newTabId, anchor: .center)
                }
              }
            }
          }
          #endif
        } else {
          // Spacer when no tabs to push new query button to the right
          Spacer()
        }

        // Divider before new query button
        if let _ = onNewQuery {
          Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
        }

        // New Query button (always present) - Fixed position
        if let newQuery = onNewQuery {
          Button(action: newQuery) {
            Image(systemName: "plus")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.secondary)
              .frame(width: 24, height: 24)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help("New Query")
          .padding(.trailing, 4)
        }
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
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.1)) {
        isHoveringTab = hovering
      }
    }
    #if os(macOS)
    .background(
      MiddleClickHandler(onMiddleClick: onClose)
    )
    #endif
  }

  private var backgroundColor: Color {
    if isActive {
      return Color.accentColor.opacity(0.15)
    } else {
      return Color.clear
    }
  }
}

#if os(macOS)
// Helper view to detect middle-click on macOS
struct MiddleClickHandler: NSViewRepresentable {
  let onMiddleClick: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = MiddleClickView()
    view.onMiddleClick = onMiddleClick
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    if let middleClickView = nsView as? MiddleClickView {
      middleClickView.onMiddleClick = onMiddleClick
    }
  }

  class MiddleClickView: NSView {
    var onMiddleClick: (() -> Void)?
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      self.wantsLayer = true

      // Monitor for other mouse down events (middle/auxiliary buttons)
      eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
        guard let self = self else { return event }

        // Check if the click is within this view's bounds
        let locationInWindow = event.locationInWindow
        let locationInView = self.convert(locationInWindow, from: nil)

        if self.bounds.contains(locationInView) && event.buttonNumber == 2 {
          self.onMiddleClick?()
          return nil  // Consume the event
        }

        return event  // Pass through if not middle click or not in bounds
      }
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    deinit {
      if let monitor = eventMonitor {
        NSEvent.removeMonitor(monitor)
      }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      return true
    }
  }
}

// macOS-specific horizontal scroller that properly handles clicks and scrolling
struct MacOSHorizontalScroller<Content: View>: NSViewRepresentable {
  let activeTabId: UUID?
  let content: Content

  init(activeTabId: UUID?, @ViewBuilder content: () -> Content) {
    self.activeTabId = activeTabId
    self.content = content()
  }

  func makeNSView(context: Context) -> HorizontalScrollView {
    let scrollView = HorizontalScrollView()
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.horizontalScrollElasticity = .automatic
    scrollView.drawsBackground = false

    let hostingController = NSHostingController(rootView: content)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false

    scrollView.documentView = hostingController.view
    context.coordinator.hostingController = hostingController

    return scrollView
  }

  func updateNSView(_ scrollView: HorizontalScrollView, context: Context) {
    context.coordinator.hostingController?.rootView = content

    // Scroll to active tab if needed
    if let activeTabId = activeTabId, context.coordinator.lastActiveTabId != activeTabId {
      context.coordinator.lastActiveTabId = activeTabId
      // Give the layout a chance to update before scrolling
      DispatchQueue.main.async {
        if let documentView = scrollView.documentView {
          let visibleRect = scrollView.documentVisibleRect
          let contentRect = documentView.frame

          // Center the visible area (simple approach - can be refined)
          let targetX = max(0, (contentRect.width - visibleRect.width) / 2)
          scrollView.contentView.scroll(to: NSPoint(x: targetX, y: 0))
        }
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator {
    var hostingController: NSHostingController<Content>?
    var lastActiveTabId: UUID?
  }

  // Custom NSScrollView that converts vertical scroll wheel to horizontal scrolling
  class HorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
      // Convert vertical scroll to horizontal
      if event.scrollingDeltaX == 0 && event.scrollingDeltaY != 0 {
        // Scroll horizontally using the vertical delta
        let currentPoint = contentView.bounds.origin
        let newX = currentPoint.x - event.scrollingDeltaY
        let maxX = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
        let clampedX = max(0, min(newX, maxX))

        contentView.scroll(to: NSPoint(x: clampedX, y: currentPoint.y))
        reflectScrolledClipView(contentView)
      } else {
        // Handle horizontal scrolling normally
        super.scrollWheel(with: event)
      }
    }
  }
}
#endif
