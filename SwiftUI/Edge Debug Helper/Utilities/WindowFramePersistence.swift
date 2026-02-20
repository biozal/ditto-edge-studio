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
    private static let minimumSize = CGSize(width: 1200, height: 700)

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

            // Clamp to minimum size, preserving the saved origin
            frame.size.width = max(frame.size.width, WindowFrameRestorer.minimumSize.width)
            frame.size.height = max(frame.size.height, WindowFrameRestorer.minimumSize.height)

            // Ensure the frame is on a visible screen before restoring
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                window.setFrame(frame, display: true, animate: false)
            } else {
                // Saved position is off-screen — use size but re-center
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
