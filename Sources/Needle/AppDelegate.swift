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
    private var rotateLongTextMenuItem: NSMenuItem?
    private var playPauseMenuItem: NSMenuItem?
    private var previousMenuItem: NSMenuItem?
    private var nextMenuItem: NSMenuItem?
    private var trackSubscription: AnyCancellable?
    private var rotateLongTextSubscription: AnyCancellable?

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
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: settings.overlaySize.width,
            height: settings.overlaySize.height
        )

        let panel = FloatingOverlayPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.minSize = OverlaySizeRules.minimumSize
        panel.maxSize = OverlaySizeRules.maximumSize
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        panel.setFrame(Self.launchFrame(for: panel), display: true)
        self.panel = panel

        configureMenuBarItem(player: player)
        configureRotateLongTextSubscription()
        player.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let panel {
            OverlayPositionStore.save(origin: panel.frame.origin)
            OverlayPositionStore.save(size: panel.frame.size)
        }
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
            panel.setFrame(Self.launchFrame(for: panel), display: true)
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

    @objc private func toggleRotateLongText() {
        settings.rotatesLongText.toggle()
    }

    @objc private func quitNeedle() {
        NSApp.terminate(nil)
    }

    private func configureMenuBarItem(player: SpotifyPlayer) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
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

        let rotateLongTextMenuItem = NSMenuItem(
            title: "Rotate Long Text",
            action: #selector(toggleRotateLongText),
            keyEquivalent: ""
        )
        rotateLongTextMenuItem.target = self
        menu.addItem(rotateLongTextMenuItem)
        self.rotateLongTextMenuItem = rotateLongTextMenuItem

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
        updateRotateLongTextMenuItem()
    }

    private func configureRotateLongTextSubscription() {
        rotateLongTextSubscription = settings.$rotatesLongText
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateRotateLongTextMenuItem()
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

    private func updateRotateLongTextMenuItem() {
        rotateLongTextMenuItem?.state = settings.rotatesLongText ? .on : .off
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

    private static func launchFrame(for panel: NSPanel) -> NSRect {
        let size = panel.frame.size
        let origin = OverlayPositionStore.savedOrigin() ?? defaultFrame(for: panel).origin
        return clampedFrame(origin: origin, size: size)
    }

    private static func clampedFrame(origin: NSPoint, size: NSSize) -> NSRect {
        let proposedFrame = NSRect(origin: origin, size: size)
        let visibleFrame = screen(for: proposedFrame)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(
            max(origin.x, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - size.width)
        )
        let y = min(
            max(origin.y, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - size.height)
        )

        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private static func screen(for frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return containingScreen
        }

        return NSScreen.screens.max { lhs, rhs in
            area(of: lhs.frame.intersection(frame)) < area(of: rhs.frame.intersection(frame))
        }
    }

    private static func area(of rect: NSRect) -> CGFloat {
        guard !rect.isNull else { return 0 }
        return rect.width * rect.height
    }

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
            image.accessibilityDescription = "Needle"
        }

        NSColor.black.setStroke()

        let record = NSBezierPath(ovalIn: NSRect(x: 3.5, y: 4.5, width: 9, height: 9))
        record.lineWidth = 1.3
        record.stroke()

        let spindle = NSBezierPath(ovalIn: NSRect(x: 7.1, y: 8.1, width: 1.8, height: 1.8))
        spindle.lineWidth = 1
        spindle.stroke()

        let arm = NSBezierPath()
        arm.move(to: NSPoint(x: 13.8, y: 13.2))
        arm.line(to: NSPoint(x: 8.8, y: 8.9))
        arm.lineCapStyle = .round
        arm.lineWidth = 1.8
        arm.stroke()

        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: 8.6, y: 8.7))
        tip.line(to: NSPoint(x: 7.6, y: 6.2))
        tip.lineCapStyle = .round
        tip.lineWidth = 1.3
        tip.stroke()

        let head = NSBezierPath(
            roundedRect: NSRect(x: 12.3, y: 12.1, width: 3.3, height: 2.4),
            xRadius: 0.8,
            yRadius: 0.8
        )
        head.lineWidth = 1.2
        head.stroke()

        return image
    }

    private static func truncatedMenuTitle(_ value: String) -> String {
        let limit = 54
        guard value.count > limit else { return value }
        let index = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<index]) + "..."
    }
}

final class FloatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
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
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        worksWhenModal = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}
