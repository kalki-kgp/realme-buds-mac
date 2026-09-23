import AppKit
import Combine
import SwiftUI

@main
struct BudsApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// A borderless panel that can take key focus, so its switches and popovers work.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let buds = BudsClient()
    private let nav = SettingsNavigation()
    private var statusItem: NSStatusItem!
    private var panel: GlassPanel!
    private var panelHost: NSView!
    private var settingsWindow: NSWindow?
    private var stage: NSWindow?
    private static let panelMargin: CGFloat = 24
    private var clickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "BudsStatusItem"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageLeading
        buildPanel()

        // The icon dims while the buds are away and shows the lower bud's charge when they're here.
        buds.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                    self?.fitPanel()
                }
            }
            .store(in: &cancellables)
        updateStatusItem()

        // BUDS_STAGE=<image> puts a backdrop behind the app's own windows, for README screenshots.
        if let path = ProcessInfo.processInfo.environment["BUDS_STAGE"], let image = NSImage(contentsOfFile: path),
           let screen = NSScreen.main {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.image = image
            view.imageScaling = .scaleAxesIndependently
            window.contentView = view
            window.ignoresMouseEvents = true
            // Above ordinary windows so nothing else lands between it and the app's surfaces.
            window.level = .floating
            window.setFrame(screen.frame, display: true)
            NSApp.activate()
            window.orderFrontRegardless()
            stage = window
        }

        // BUDS_OPEN=panel|settings[:page] opens a surface at launch, for screenshots while developing.
        if let open = ProcessInfo.processInfo.environment["BUDS_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                let parts = open.split(separator: ":").map(String.init)
                if parts[0] == "settings" {
                    if parts.count > 1, let page = SettingsPage(rawValue: parts[1]) { self.nav.page = page }
                    self.showSettings()
                } else {
                    self.showPanel()
                }
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Buds")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = buds.link != .connected
        let levels = [Bud.left, .right].compactMap { buds.battery[$0]?.percent }
        let text = buds.link == .connected ? levels.min().map { " \($0)%" } ?? "" : ""
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
        ])
    }

    // MARK: Panel

    private func buildPanel() {
        panel = GlassPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window server shadows the panel's rectangular bounds, not the rounded glass,
        // which draws a hard square outline around the corners. The glass carries its own edge.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        // SwiftUI's glass clipped to the panel's shape. An NSGlassEffectView tinted its whole
        // rectangle faintly, which showed as a square just outside the rounded corners.
        // The margin gives Liquid Glass's own soft shadow room to fade out; a borderless window
        // clips at its rectangle, so without it the shadow ended in a faint square at the corners.
        let root = PanelView(buds: buds, openSettings: { [weak self] in self?.showSettings() })
            .background(WindowGlass())
            .buttonBorderShape(.capsule)
            .padding(Self.panelMargin)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        panelHost = host
    }

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        buds.refresh()
        let size = panelHost.fittingSize
        let screen = (buttonWindow.screen ?? NSScreen.main!).visibleFrame
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // A menu bar manager can park the icon off-screen; fall back to the top-right corner then.
        let onScreen = buttonWindow.occlusionState.contains(.visible) && screen.insetBy(dx: 0, dy: -40).contains(NSPoint(x: anchor.midX, y: screen.maxY))
        let m = Self.panelMargin
        var x = onScreen ? anchor.midX - size.width / 2 : screen.maxX - size.width + m - 8
        x = min(max(x, screen.minX + 8 - m), screen.maxX - size.width + m - 8)
        let top = (onScreen ? anchor.minY - 6 : screen.maxY - 6) + m
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        if stage != nil { panel.center() }

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        button.highlight(true)

        // Clicks in any other app close the panel; our own popovers and Settings don't.
        // A debug launch (BUDS_OPEN) keeps it pinned so it can be screenshotted.
        guard ProcessInfo.processInfo.environment["BUDS_OPEN"] == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    /// Keeps the panel's height following its content (ANC levels, offline card, last touch),
    /// pinned at the top edge.
    private func fitPanel() {
        guard panel.isVisible else { return }
        let size = panelHost.fittingSize
        guard abs(size.height - panel.frame.height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    private func hidePanel() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        statusItem.button?.highlight(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.panel.orderOut(nil) })
    }

    // MARK: Settings

    private func showSettings() {
        hidePanel()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            WindowChrome.configure(window)
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.title = "Buds Settings"

            // The glass is SwiftUI's, clipped to the window's radius; an NSGlassEffectView as the
            // content view left the system frame drawing its own corners around it.
            // Droppy Code's arrangement: a plain container holding a hosting view that the window
            // sizes, with no safe area, so the glass runs up under the title bar to the corners.
            let root = SettingsView(buds: buds, nav: nav)
                .background(WindowGlass())
                .buttonBorderShape(.capsule)
            let frame = NSRect(origin: .zero, size: window.frame.size)
            let hosting = WindowHostingView(rootView: AnyView(root))
            hosting.frame = frame
            let container = NSView(frame: frame)
            container.addSubview(hosting)
            window.contentView = container
            window.center()
            settingsWindow = window
        }
        // A settings window needs the app in front, which an accessory app is not by default.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        guard let window = settingsWindow else { return }
        if stage != nil { window.center() }
        window.makeKeyAndOrderFront(nil)
        if let stage {
            window.level = NSWindow.Level(rawValue: stage.level.rawValue + 1)
            window.order(.above, relativeTo: stage.windowNumber)
        }
        WindowChrome.placeTrafficLights(on: window)
        // The shadow is traced from what's drawn, so retrace it once the glass is on screen.
        DispatchQueue.main.async { window.invalidateShadow() }
    }

    func windowDidResize(_ notification: Notification) {
        (notification.object as? NSWindow)?.invalidateShadow()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Lets the window frame define the hosting view's size instead of the content hugging it.
final class WindowHostingView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
