#if os(macOS)
import AppKit
import SwiftUI

// MARK: - WindowFrameRestorer

/// Attaches to an NSWindow via NSViewRepresentable and:
/// - Restores the last saved MainStudioView frame from UserDefaults on first appearance
/// - Automatically saves the frame to UserDefaults whenever the window moves or resizes
///
/// Usage: attach as a zero-size background on the outermost view in MainStudioView.
///   .background(WindowFrameRestorer())
struct WindowFrameRestorer: NSViewRepresentable {
    private static let frameKey = "EdgeStudio.MainStudioWindowFrame"
    private static let minimumSize = CGSize(width: 960, height: 680)

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.setup(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        func setup(window: NSWindow) {
            guard self.window == nil else { return } // only run once
            self.window = window

            restoreFrame(in: window)
            attachObservers(to: window)
        }

        // MARK: Private

        private func restoreFrame(in window: NSWindow) {
            guard let saved = UserDefaults.standard.string(forKey: WindowFrameRestorer.frameKey) else {
                // No saved frame — enforce minimum size if the window is too small
                enforceMinimum(in: window)
                return
            }

            var frame = NSRectFromString(saved)

            // Clamp to minimum size
            frame.size.width = max(frame.size.width, WindowFrameRestorer.minimumSize.width)
            frame.size.height = max(frame.size.height, WindowFrameRestorer.minimumSize.height)

            // Find the screen with the greatest overlap with the saved frame
            let targetScreen = NSScreen.screens.max(by: { lhs, rhs in
                let lhsIntersect = lhs.visibleFrame.intersection(frame)
                let rhsIntersect = rhs.visibleFrame.intersection(frame)
                return (lhsIntersect.width * lhsIntersect.height) < (rhsIntersect.width * rhsIntersect.height)
            })

            if let screen = targetScreen, !screen.visibleFrame.intersection(frame).isEmpty {
                let visible = screen.visibleFrame

                // Clamp window size so it never exceeds the screen
                frame.size.width = min(frame.size.width, visible.width)
                frame.size.height = min(frame.size.height, visible.height)

                // Clamp origin so the window is fully on-screen
                frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.size.width))
                frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.size.height))

                window.setFrame(frame, display: true, animate: false)
            } else {
                // Saved position is fully off-screen — use size but re-center
                window.setContentSize(frame.size)
                window.center()
            }
        }

        private func enforceMinimum(in window: NSWindow) {
            let current = window.frame
            let needsResize = current.width < WindowFrameRestorer.minimumSize.width ||
                current.height < WindowFrameRestorer.minimumSize.height
            if needsResize {
                window.setContentSize(NSSize(
                    width: max(current.width, WindowFrameRestorer.minimumSize.width),
                    height: max(current.height, WindowFrameRestorer.minimumSize.height)
                ))
            }
        }

        private func attachObservers(to window: NSWindow) {
            let center = NotificationCenter.default

            observers.append(center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.saveFrame()
            })

            observers.append(center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.saveFrame()
            })
        }

        private func saveFrame() {
            guard let window else { return }
            UserDefaults.standard.set(
                NSStringFromRect(window.frame),
                forKey: WindowFrameRestorer.frameKey
            )
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
#endif
