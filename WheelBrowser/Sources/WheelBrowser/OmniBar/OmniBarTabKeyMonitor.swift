import SwiftUI
import AppKit

/// Captures plain Tab / Shift-Tab while the OmniBar is active so keyboard
/// navigation cannot fall through into the underlying page or AppKit key loop.
struct OmniBarTabKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onTabPress: (_ isShiftTab: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        context.coordinator.attach(to: view)
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onTabPress = onTabPress
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onTabPress = onTabPress
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class MonitorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    final class Coordinator {
        weak var view: MonitorView?
        var isEnabled = false
        var onTabPress: ((_ isShiftTab: Bool) -> Void)?

        private var keyMonitor: Any?

        func attach(to view: MonitorView) {
            self.view = view
            installMonitorIfNeeded()
        }

        func detach() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
            view = nil
        }

        private func installMonitorIfNeeded() {
            guard keyMonitor == nil else { return }

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  let view,
                  let window = view.window,
                  event.window === window,
                  event.keyCode == 48 else {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let disallowedFlags: NSEvent.ModifierFlags = [.command, .control, .option, .function]
            guard flags.intersection(disallowedFlags).isEmpty else {
                return event
            }

            let allowedFlags: NSEvent.ModifierFlags = [.shift, .capsLock]
            guard flags.subtracting(allowedFlags).isEmpty else {
                return event
            }

            onTabPress?(flags.contains(.shift))
            return nil
        }

        deinit {
            detach()
        }
    }
}
