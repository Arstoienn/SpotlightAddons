import AppKit
import SwiftUI

// A note on the screen, for a moment, when the app is opened: Spotlight Add-ons has no window and
// no Dock icon, so without it nothing says that opening it did anything. It says too when the
// permission it needs has not been given, and stays until it has.
final class Welcome {
    enum State { case running, waitingForPermission }

    private var panel: NSPanel?
    private let model = WelcomeModel()
    private var generation = 0

    func show(_ state: State) {
        guard Prefs.welcome else { return }
        model.state = state
        generation += 1
        let mine = generation
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        if panel.alphaValue < 1 || !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
        // A note about the permission stays until it is given; the other goes of itself.
        guard state == .running else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, generation == mine else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; panel.animator().alphaValue = 0 }) {
                if self.generation == mine { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 72), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: WelcomeView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 72)
        panel.contentView = host
        return panel
    }

    // Top centre of the display the pointer is on, just under the menu bar.
    private func place(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.maxY - panel.frame.height - 14))
    }
}

@Observable final class WelcomeModel {
    var state = Welcome.State.running
}

struct WelcomeView: View {
    var model: WelcomeModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.state == .running ? "plus.magnifyingglass" : "lock")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.state == .running ? "Spotlight Add-ons is running" : "Spotlight Add-ons needs permission")
                    .font(.system(size: 15, weight: .semibold))
                Text(model.state == .running
                     ? "Type into Spotlight, and the answer appears above it."
                     : "Allow it under System Settings, Privacy & Security, Accessibility.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(width: 360, height: 72)
        .spotlightGlass()
    }
}
