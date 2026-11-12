import AppKit
import ServiceManagement

/// Borderless panel that can take keyboard focus and reports when it loses it.
final class GamePanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: GamePanel!
    private let gameView = GameView(frame: NSRect(origin: .zero, size: GameView.size))
    private var lastHide = Date.distantPast
    private var clickMonitor: Any?

    private static let difficultyKey = "difficulty"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Normal unless the player has chosen otherwise (integer(forKey:) would read "unset" as 0 = Easy).
        let saved = UserDefaults.standard.object(forKey: Self.difficultyKey) as? Int
        gameView.game.difficulty = saved.flatMap(Difficulty.init(rawValue:)) ?? .normal
        gameView.onEscape = { [weak self] in self?.hidePanel() }

        buildPanel()

        // Switching to another app closes the game too.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.setAccessibilityLabel("Ping")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - panel

    private func buildPanel() {
        let size = GameView.size
        let radius: CGFloat = 26

        let content: NSView
        if #available(macOS 26.0, *) {
            // Liquid Glass.
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = radius
            glass.contentView = gameView
            content = glass
        } else {
            let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = radius
            blur.layer?.masksToBounds = true
            gameView.frame = blur.bounds
            gameView.autoresizingMask = [.width, .height]
            blur.addSubview(gameView)
            content = blur
        }

        panel = GamePanel(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = content
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.onResignKey = { [weak self] in self?.hidePanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        var x = anchor.midX - panel.frame.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - panel.frame.height - 6))

        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(gameView)
        gameView.activate()

        // Menu bar items such as Sound or Wi-Fi belong to other processes, so clicking them never takes key
        // focus from the panel. Watch for clicks anywhere else on screen and close on those.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.hidePanel() }
        }
        // Show the icon as pressed while the game is open. Set after the click finishes, or the button resets it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.statusItem.button?.highlight(true)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        lastHide = Date()
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        statusItem.button?.highlight(false)
        gameView.deactivate()
        panel.orderOut(nil)
        // Hand keyboard focus back to the app you were in; otherwise (e.g. after Esc) typing goes nowhere.
        if NSApp.isActive { NSApp.deactivate() }
    }

    // MARK: - status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showMenu()
        } else if panel.isVisible {
            hidePanel()
        } else if Date().timeIntervalSince(lastHide) > 0.25 {
            // A click on the icon first takes key focus from the panel, which closes it; without this
            // check the same click would immediately reopen it.
            showPanel()
        }
    }

    private func showMenu() {
        hidePanel()
        let menu = NSMenu()

        let difficultyMenu = NSMenu()
        for level in Difficulty.allCases {
            let item = NSMenuItem(title: level.title, action: #selector(chooseDifficulty(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = gameView.game.difficulty == level ? .on : .off
            difficultyMenu.addItem(item)
        }
        let difficultyParent = NSMenuItem(title: "Difficulty", action: nil, keyEquivalent: "")
        difficultyParent.submenu = difficultyMenu
        menu.addItem(difficultyParent)

        let reset = NSMenuItem(title: "New Match", action: #selector(newMatch), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ping", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Attach the menu only for this click so a plain left click keeps opening the game.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func chooseDifficulty(_ sender: NSMenuItem) {
        guard let level = Difficulty(rawValue: sender.tag) else { return }
        gameView.game.difficulty = level
        UserDefaults.standard.set(level.rawValue, forKey: Self.difficultyKey)
        gameView.game.resetScore()
    }

    @objc private func newMatch() { gameView.game.resetScore() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSSound.beep()
        }
    }

    /// Two horizontal paddles and a ball, drawn as a template image so the system tints it.
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 12.6, width: 8, height: 2.4), xRadius: 1.2, yRadius: 1.2).fill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 1, width: 8, height: 2.4), xRadius: 1.2, yRadius: 1.2).fill()
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 6.2, width: 3.6, height: 3.6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
