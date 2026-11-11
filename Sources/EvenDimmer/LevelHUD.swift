import AppKit
import SwiftUI

/// A small on-screen indicator, like macOS's own brightness overlay, shown when the
/// brightness keys move into extra dim (macOS doesn't show its own overlay then).
@MainActor
final class LevelHUD {
    static let shared = LevelHUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = HUDModel()

    func show(symbol: String, title: String, level: Double) {
        model.symbol = symbol
        model.title = title
        model.level = min(max(level, 0), 1)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = panel.frame.size
            let origin = NSPoint(x: screen.frame.midX - size.width / 2,
                                 y: screen.frame.minY + screen.frame.height * 0.14)
            panel.setFrameOrigin(origin)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                                 completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }
}

private final class HUDModel: ObservableObject {
    @Published var symbol = "sun.min"
    @Published var title = ""
    @Published var level = 0.0
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: model.symbol)
                .font(.system(size: 64, weight: .regular))
            Text(model.title)
                .font(.system(size: 13, weight: .medium))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.15))
                    Capsule().fill(.primary.opacity(0.8))
                        .frame(width: max(6, geo.size.width * model.level))
                }
            }
            .frame(height: 6)
        }
        .foregroundStyle(.primary)
        .padding(24)
        .frame(width: 200, height: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
