import AppKit
import SwiftUI

/// Shows a borderless, rounded, click-through panel with the new device name and volume, then fades it out.
@MainActor
final class HUDController {
    static let shared = HUDController()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(name: String, scope: AudioScope, volume: Float?) {
        let defaults = UserDefaults.standard
        let duration = max(0.5, defaults.double(forKey: "hudDuration"))
        let position = defaults.string(forKey: "hudPosition") ?? "bottom"
        let size = NSSize(width: 260, height: 120)

        let panel = self.panel ?? makePanel(size: size)
        self.panel = panel
        panel.contentView = NSHostingView(rootView: HUDView(name: name, scope: scope, volume: volume))
        if let screen = NSScreen.main?.visibleFrame {
            let x = screen.midX - size.width / 2
            let y: CGFloat
            switch position {
            case "top": y = screen.maxY - size.height - 40
            case "center": y = screen.midY - size.height / 2
            default: y = screen.minY + 80
            }
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 },
                                                completionHandler: { panel.orderOut(nil) })
        }
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

/// SwiftUI content of the HUD panel.
private struct HUDView: View {
    let name: String
    let scope: AudioScope
    let volume: Float?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: scope == .output ? "speaker.wave.2.fill" : "mic.fill")
                .font(.system(size: 30))
            Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
            if let volume {
                ProgressView(value: Double(volume)).progressViewStyle(.linear).frame(width: 180)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
