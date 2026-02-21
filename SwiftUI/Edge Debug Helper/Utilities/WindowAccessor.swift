#if os(macOS)
import AppKit
import SwiftUI

/// Provides reliable NSWindow access for the view.
/// Uses viewDidMoveToWindow() instead of NSApplication.shared.keyWindow,
/// which can return nil during SwiftUI transitions.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        HostingView(configure: configure)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HostingView: NSView {
        let configure: (NSWindow) -> Void

        init(configure: @escaping (NSWindow) -> Void) {
            self.configure = configure
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                self.configure(window)
            }
        }
    }
}
#endif
