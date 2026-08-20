import AppKit
import SwiftUI

@main
enum SavedToActionDesktopMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = SavedToActionAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class SavedToActionAppDelegate: NSObject, NSApplicationDelegate {
    private let model = ActionModel()
    private var panel: DesktopActionPanel?
    private var boardWindow: NSWindow?
    private var boardCoordinator: BoardWebView.Coordinator?
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createStatusItem()
        createDesktopPanel()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.reload()
                self?.boardCoordinator?.pushPayload()
            }
        }
    }

    private func createDesktopPanel() {
        let size = NSSize(width: 438, height: 500)
        let panel = DesktopActionPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.contentView = NSHostingView(rootView: DesktopCardView(model: model) { [weak self] in
            self?.showBoard()
        })
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 34, y: frame.maxY - size.height - 32))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: "Saved to Action")
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "显示或隐藏桌面卡片", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let board = NSMenuItem(title: "打开完整看板", action: #selector(showBoardFromMenu), keyEquivalent: "")
        board.target = self
        menu.addItem(board)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Saved to Action", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { model.reload(); panel.orderFrontRegardless() }
    }

    @objc private func showBoardFromMenu() { showBoard() }

    private func showBoard() {
        if boardWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "收藏行动看板"
            window.minSize = NSSize(width: 840, height: 620)
            window.isReleasedWhenClosed = false
            let board = BoardWebView.makeStandalone(model: model)
            window.contentView = board.webView
            boardCoordinator = board.coordinator
            window.center()
            boardWindow = window
        }
        model.reload()
        boardCoordinator?.pushPayload()
        NSApplication.shared.activate(ignoringOtherApps: true)
        boardWindow?.makeKeyAndOrderFront(nil)
        boardWindow?.orderFrontRegardless()
    }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

final class DesktopActionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
