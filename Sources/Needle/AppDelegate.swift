import AppKit
import Combine
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = OverlaySettings()
    private var panel: FloatingOverlayPanel?
    private var player: SpotifyPlayer?
    private var statusItem: NSStatusItem?
    private var nowPlayingMenuItem: NSMenuItem?
    private var overlayMenuItem: NSMenuItem?
    private var layoutMenuItems: [OverlayLayout: NSMenuItem] = [:]
    private var playPauseMenuItem: NSMenuItem?
    private var previousMenuItem: NSMenuItem?
    private var nextMenuItem: NSMenuItem?
    private var trackSubscription: AnyCancellable?
    private var layoutSubscription: AnyCancellable?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let player = SpotifyPlayer()
        self.player = player

        let contentView = OverlayView(player: player, settings: settings)
        let hostingView = DraggableHostingView(rootView: contentView)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: settings.layout.metrics.width,
            height: settings.layout.metrics.height
        )

        let panel = FloatingOverlayPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        panel.setFrame(Self.defaultFrame(for: panel), display: true)
        self.panel = panel

        configureMenuBarItem(player: player)
        configureLayoutSubscription()
        player.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        player?.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    @objc private func toggleOverlay() {
        guard let panel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            panel.setFrame(Self.defaultFrame(for: panel), display: true)
        }

        updateOverlayMenuItem()
    }

    @objc private func playPause() {
        player?.playPause()
    }

    @objc private func previousTrack() {
        player?.previousTrack()
    }

    @objc private func nextTrack() {
        player?.nextTrack()
    }

    @objc private func setLayout(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let layout = OverlayLayout(rawValue: rawValue) else {
            return
        }

        settings.layout = layout
    }

    @objc private func quitNeedle() {
        NSApp.terminate(nil)
    }

    private func configureMenuBarItem(player: SpotifyPlayer) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Needle")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.appearsDisabled = false
            button.contentTintColor = .labelColor
            button.toolTip = "Needle"
        }

        let menu = NSMenu()

        let nowPlayingMenuItem = NSMenuItem(title: "Needle is waiting", action: nil, keyEquivalent: "")
        nowPlayingMenuItem.isEnabled = false
        menu.addItem(nowPlayingMenuItem)
        self.nowPlayingMenuItem = nowPlayingMenuItem

        menu.addItem(.separator())

        let overlayMenuItem = NSMenuItem(title: "Hide Overlay", action: #selector(toggleOverlay), keyEquivalent: "")
        overlayMenuItem.target = self
        menu.addItem(overlayMenuItem)
        self.overlayMenuItem = overlayMenuItem

        menu.addItem(.separator())

        let layoutMenu = NSMenu()
        for layout in OverlayLayout.allCases {
            let item = NSMenuItem(title: layout.title, action: #selector(setLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.rawValue
            layoutMenu.addItem(item)
            layoutMenuItems[layout] = item
        }

        let layoutMenuItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        layoutMenuItem.submenu = layoutMenu
        menu.addItem(layoutMenuItem)

        menu.addItem(.separator())

        let playPauseMenuItem = NSMenuItem(title: "Play/Pause", action: #selector(playPause), keyEquivalent: "")
        playPauseMenuItem.target = self
        menu.addItem(playPauseMenuItem)
        self.playPauseMenuItem = playPauseMenuItem

        let previousMenuItem = NSMenuItem(title: "Previous Track", action: #selector(previousTrack), keyEquivalent: "")
        previousMenuItem.target = self
        menu.addItem(previousMenuItem)
        self.previousMenuItem = previousMenuItem

        let nextMenuItem = NSMenuItem(title: "Next Track", action: #selector(nextTrack), keyEquivalent: "")
        nextMenuItem.target = self
        menu.addItem(nextMenuItem)
        self.nextMenuItem = nextMenuItem

        menu.addItem(.separator())

        let quitMenuItem = NSMenuItem(title: "Quit Needle", action: #selector(quitNeedle), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu

        trackSubscription = player.trackPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                self?.updateMenuBarItem(for: track)
            }

        updateMenuBarItem(for: player.track)
        updateOverlayMenuItem()
        updateLayoutMenuItems()
    }

    private func configureLayoutSubscription() {
        layoutSubscription = settings.$layout
            .receive(on: RunLoop.main)
            .sink { [weak self] layout in
                self?.resizePanel(for: layout)
                self?.updateLayoutMenuItems()
            }
    }

    private func updateMenuBarItem(for track: TrackState) {
        let title: String
        if track.isAvailable {
            title = "\(track.title) - \(track.artist)"
        } else {
            title = track.title
        }

        nowPlayingMenuItem?.title = Self.truncatedMenuTitle(title)
        playPauseMenuItem?.title = track.isPlaying ? "Pause" : "Play"
        playPauseMenuItem?.isEnabled = track.isAvailable
        previousMenuItem?.isEnabled = track.isAvailable
        nextMenuItem?.isEnabled = track.isAvailable

        if let button = statusItem?.button {
            button.toolTip = "Needle: \(title)"
            button.contentTintColor = .labelColor
        }
    }

    private func updateOverlayMenuItem() {
        overlayMenuItem?.title = panel?.isVisible == true ? "Hide Overlay" : "Show Overlay"
    }

    private func updateLayoutMenuItems() {
        for (layout, item) in layoutMenuItems {
            item.state = layout == settings.layout ? .on : .off
        }
    }

    private func resizePanel(for layout: OverlayLayout) {
        guard let panel else { return }

        let metrics = layout.metrics
        let currentFrame = panel.frame
        let newSize = NSSize(width: metrics.width, height: metrics.height)
        let newOrigin = NSPoint(
            x: currentFrame.maxX - newSize.width,
            y: currentFrame.maxY - newSize.height
        )
        let newFrame = NSRect(origin: newOrigin, size: newSize)

        panel.contentView?.frame = NSRect(origin: .zero, size: newSize)
        panel.setFrame(newFrame, display: true, animate: true)
    }

    private static func defaultFrame(for panel: NSPanel) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 28,
            y: visibleFrame.maxY - size.height - 24
        )
        return NSRect(origin: origin, size: size)
    }

    private static func truncatedMenuTitle(_ value: String) -> String {
        let limit = 54
        guard value.count > limit else { return value }
        let index = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<index]) + "..."
    }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class FloatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        worksWhenModal = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}
