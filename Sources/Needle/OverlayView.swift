import AppKit
import SwiftUI

enum OverlaySizeRules {
    static let minimumSize = NSSize(width: 104, height: 48)
    static let defaultSize = NSSize(width: 258, height: 78)
    static let maximumSize = NSSize(width: 380, height: 116)
    static let smallBreakpoint = NSSize(width: 150, height: 54)
    static let fullBreakpoint = NSSize(width: 286, height: 80)
    static let resizeHitSize: CGFloat = 14

    static func clamped(_ size: NSSize) -> NSSize {
        NSSize(
            width: min(max(size.width, minimumSize.width), maximumSize.width),
            height: min(max(size.height, minimumSize.height), maximumSize.height)
        )
    }
}

enum OverlayContentMode: String {
    case small
    case medium
    case full

    static func mode(for size: NSSize) -> OverlayContentMode {
        let fullWidthThreshold: CGFloat
        if size.height >= 104 {
            fullWidthThreshold = 218
        } else if size.height >= 90 {
            fullWidthThreshold = 250
        } else {
            fullWidthThreshold = OverlaySizeRules.fullBreakpoint.width
        }

        if size.width < OverlaySizeRules.smallBreakpoint.width ||
            size.height < OverlaySizeRules.smallBreakpoint.height {
            return .small
        }

        if size.width >= fullWidthThreshold &&
            size.height >= OverlaySizeRules.fullBreakpoint.height {
            return .full
        }

        return .medium
    }
}

final class OverlaySettings: ObservableObject {
    @Published private(set) var overlaySize: NSSize

    init() {
        overlaySize = OverlayPositionStore.savedSize()
            .map(OverlaySizeRules.clamped(_:))
            ?? OverlaySizeRules.defaultSize
    }

    func setOverlaySize(_ size: NSSize, persist: Bool = true) {
        let clampedSize = OverlaySizeRules.clamped(size)
        if clampedSize != overlaySize {
            overlaySize = clampedSize
        }

        if persist {
            OverlayPositionStore.save(size: clampedSize)
        }
    }
}

struct OverlayMetrics {
    let size: NSSize

    var mode: OverlayContentMode {
        OverlayContentMode.mode(for: size)
    }

    var width: CGFloat {
        size.width
    }

    var height: CGFloat {
        size.height
    }

    var shadowMargin: CGFloat {
        if mode == .small || height < 64 {
            return 6
        }

        return 8
    }

    var surfaceWidth: CGFloat {
        max(0, width - (shadowMargin * 2))
    }

    var surfaceHeight: CGFloat {
        max(0, height - (shadowMargin * 2))
    }

    var padding: CGFloat {
        switch mode {
        case .small:
            return 6
        case .medium:
            if height < 58 {
                return 2
            }

            return 4
        case .full:
            if height < 90 {
                return 8
            }

            return 10
        }
    }

    var artworkSide: CGFloat {
        guard mode == .full else {
            return 0
        }

        let reservedContentWidth: CGFloat = isNarrowFull ? 130 : 138
        let widthLimitedSide = innerWidth - columnSpacing - reservedContentWidth
        return max(42, min(innerHeight, widthLimitedSide))
    }

    var columnSpacing: CGFloat {
        guard mode == .full else {
            return 0
        }

        return isNarrowFull ? 8 : 10
    }

    var cornerRadius: CGFloat {
        mode == .full ? 9 : 6
    }

    var contentWidth: CGFloat {
        max(0, surfaceWidth - (padding * 2) - artworkSide - columnSpacing)
    }

    var innerWidth: CGFloat {
        max(0, surfaceWidth - (padding * 2))
    }

    var innerHeight: CGFloat {
        max(0, surfaceHeight - (padding * 2))
    }

    var isCompactMedium: Bool {
        mode == .medium && (height < 68 || width < 190)
    }

    var isCompactFull: Bool {
        mode == .full && (height < 96 || isNarrowFull)
    }

    var progressTrailingReserve: CGFloat {
        switch mode {
        case .small:
            return 0
        case .medium:
            return min(12, max(8, innerWidth * 0.045))
        case .full:
            return min(12, max(8, innerWidth * 0.04))
        }
    }

    var mediumTitleHeight: CGFloat {
        guard mode == .medium else {
            return 0
        }

        return mediumValue(compact: 12, regular: 16)
    }

    var mediumControlRowHeight: CGFloat {
        guard mode == .medium else {
            return 0
        }

        return mediumValue(
            compact: ControlButtonScale.small.playButtonSize,
            regular: ControlButtonScale.medium.playButtonSize
        )
    }

    var mediumRowGap: CGFloat {
        guard mode == .medium else {
            return 0
        }

        return mediumValue(compact: 3, regular: 4)
    }

    var mediumContentHeight: CGFloat {
        guard mode == .medium else {
            return innerHeight
        }

        return min(innerHeight, mediumTitleHeight + mediumRowGap + mediumControlRowHeight)
    }

    private var isNarrowFull: Bool {
        mode == .full && width < OverlaySizeRules.fullBreakpoint.width
    }

    var mediumExpansion: CGFloat {
        guard mode == .medium else {
            return 0
        }

        let heightFactor = unitInterval((height - 58) / 20)
        let widthFactor = unitInterval((width - 190) / 68)
        return min(heightFactor, widthFactor)
    }

    func mediumValue(compact: CGFloat, regular: CGFloat) -> CGFloat {
        compact + ((regular - compact) * mediumExpansion)
    }

    private func unitInterval(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}

struct OverlayView: View {
    @ObservedObject var player: SpotifyPlayer
    @ObservedObject var settings: OverlaySettings
    @StateObject private var artwork = ArtworkLoader()
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        let metrics = OverlayMetrics(size: settings.overlaySize)

        ZStack {
            ZStack {
                GlassPanel(cornerRadius: metrics.cornerRadius)
                    .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))

                ZStack {
                    layoutContent(for: metrics.mode, metrics: metrics)
                        .padding(metrics.padding)
                        .frame(width: metrics.surfaceWidth, height: metrics.surfaceHeight)

                    ResizeCornerMark()
                        .frame(width: 10, height: 10)
                        .padding(.trailing, 5)
                        .padding(.bottom, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(false)

                    PanelInteractionSurface(
                        mode: metrics.mode,
                        metrics: metrics
                    )
                    .id(metrics.mode.rawValue)
                    .frame(width: metrics.surfaceWidth, height: metrics.surfaceHeight)
                }
                .frame(width: metrics.surfaceWidth, height: metrics.surfaceHeight)
                .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
            }
            .frame(width: metrics.surfaceWidth, height: metrics.surfaceHeight)

            PanelResizeSurface(settings: settings)
                .frame(width: OverlaySizeRules.resizeHitSize, height: OverlaySizeRules.resizeHitSize)
                .padding(.trailing, metrics.shadowMargin)
                .padding(.bottom, metrics.shadowMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: metrics.width, height: metrics.height)
        .contextMenu {
            Button("Quit Needle") {
                NSApp.terminate(nil)
            }
        }
        .onAppear {
            artwork.load(player.track.artworkURL)
            scrubPosition = player.track.position
        }
        .onChange(of: player.track) { track in
            artwork.load(track.artworkURL)
            if !isScrubbing {
                scrubPosition = track.position
            }
        }
    }

    @ViewBuilder
    private func layoutContent(for mode: OverlayContentMode, metrics: OverlayMetrics) -> some View {
        switch mode {
        case .full:
            bigLayout(metrics: metrics)
        case .medium:
            mediumLayout(metrics: metrics)
        case .small:
            smallLayout
        }
    }

    @ViewBuilder
    private func bigLayout(metrics: OverlayMetrics) -> some View {
        if metrics.isCompactFull {
            compactBigLayout(metrics: metrics)
        } else {
            regularBigLayout(metrics: metrics)
        }
    }

    private func regularBigLayout(metrics: OverlayMetrics) -> some View {
        HStack(alignment: .top, spacing: metrics.columnSpacing) {
            ArtworkView(image: artwork.image, isAvailable: player.track.isAvailable)
                .frame(width: metrics.artworkSide, height: metrics.artworkSide)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .panelArtworkInteraction(openSpotify: openSpotify)

            VStack(alignment: .leading, spacing: 0) {
                bigMetadataHeader(metrics: metrics)
                    .frame(width: metrics.contentWidth, alignment: .leading)

                Spacer(minLength: 0)

                controls(
                    buttonScale: .regular,
                    spacing: 6,
                    fillsWidth: false
                )
                .frame(width: metrics.contentWidth, alignment: .leading)

                Spacer(minLength: 0)

                progress
                    .frame(
                        width: max(1, metrics.contentWidth - metrics.progressTrailingReserve),
                        height: 13,
                        alignment: .bottom
                    )
            }
            .frame(width: metrics.contentWidth, height: metrics.artworkSide, alignment: .top)
        }
        .frame(width: metrics.innerWidth, height: metrics.innerHeight, alignment: .topLeading)
    }

    private func compactBigLayout(metrics: OverlayMetrics) -> some View {
        let buttonSpacing: CGFloat = 5
        let buttonScale = ControlButtonScale.small
        let controlsWidth = buttonScale.width(spacing: buttonSpacing)

        return HStack(alignment: .top, spacing: metrics.columnSpacing) {
            ArtworkView(image: artwork.image, isAvailable: player.track.isAvailable)
                .frame(width: metrics.artworkSide, height: metrics.artworkSide)
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .panelArtworkInteraction(openSpotify: openSpotify)

            VStack(alignment: .leading, spacing: 0) {
                bigMetadataHeader(metrics: metrics)
                    .frame(width: metrics.contentWidth, alignment: .leading)

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 6) {
                    controls(
                        buttonScale: buttonScale,
                        spacing: buttonSpacing,
                        fillsWidth: false
                    )
                        .frame(width: controlsWidth, alignment: .leading)

                    progress
                        .frame(height: 13, alignment: .center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.trailing, metrics.progressTrailingReserve)
                }
                .frame(width: metrics.contentWidth, alignment: .leading)
            }
            .frame(width: metrics.contentWidth, height: metrics.artworkSide, alignment: .top)
        }
        .frame(width: metrics.innerWidth, height: metrics.innerHeight, alignment: .topLeading)
    }

    private func mediumLayout(metrics: OverlayMetrics) -> some View {
        let titleHeight: CGFloat = metrics.mediumTitleHeight
        let artistHeight: CGFloat = titleHeight
        let metadataFontSize: CGFloat = metrics.mediumValue(compact: 11.5, regular: 13)
        let rowSpacing: CGFloat = metrics.mediumValue(compact: 5, regular: 8)
        let buttonSpacing: CGFloat = metrics.mediumValue(compact: 4, regular: 6)
        let buttonScale = ControlButtonScale(
            sideButtonSize: metrics.mediumValue(
                compact: ControlButtonScale.small.sideButtonSize,
                regular: ControlButtonScale.medium.sideButtonSize
            ),
            playButtonSize: metrics.mediumControlRowHeight
        )
        let controlsWidth = buttonScale.width(spacing: buttonSpacing)
        let compactArtistWidth = metrics.mediumValue(compact: 48, regular: 58)
        let artistWidthFraction = metrics.mediumValue(compact: 0.32, regular: 0.36)
        let artistWidth = min(
            82,
            max(compactArtistWidth, metrics.innerWidth * artistWidthFraction)
        )

        return VStack(alignment: .leading, spacing: metrics.mediumRowGap) {
            HStack(alignment: .top, spacing: 8) {
                trackText(
                    player.track.title,
                    font: .system(size: metadataFontSize, weight: .semibold, design: .rounded),
                    foregroundStyle: AnyShapeStyle(.primary),
                    height: titleHeight,
                    alignment: .leading,
                    shadow: TextShadow(color: .black.opacity(0.40), radius: 2, x: 0, y: 1)
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())

                trackText(
                    player.track.artist,
                    font: .system(size: metadataFontSize, weight: .medium, design: .rounded),
                    foregroundStyle: AnyShapeStyle(.secondary.opacity(0.92)),
                    height: artistHeight,
                    alignment: .trailing,
                    shadow: TextShadow(color: .black.opacity(0.30), radius: 2, x: 0, y: 1)
                )
                    .frame(width: artistWidth, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .frame(width: metrics.innerWidth, alignment: .center)

            HStack(alignment: .center, spacing: rowSpacing) {
                controls(
                    buttonScale: buttonScale,
                    spacing: buttonSpacing,
                    fillsWidth: false
                )
                    .frame(width: controlsWidth, alignment: .leading)

                progress
                    .frame(height: 13, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.trailing, metrics.progressTrailingReserve)
            }
            .frame(width: metrics.innerWidth, alignment: .center)
        }
        .frame(width: metrics.innerWidth, height: metrics.mediumContentHeight, alignment: .topLeading)
        .frame(width: metrics.innerWidth, height: metrics.innerHeight, alignment: .center)
    }

    private var smallLayout: some View {
        controls(buttonScale: .small, spacing: 5, fillsWidth: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func bigMetadataHeader(metrics: OverlayMetrics) -> some View {
        let titleHeight: CGFloat = metrics.isCompactFull ? 14 : 16
        let artistHeight: CGFloat = titleHeight
        let metadataFontSize: CGFloat = metrics.isCompactFull ? 11.5 : 13
        let timerFontSize: CGFloat = metrics.isCompactFull ? 8.4 : 9.5
        let timerWidth: CGFloat = metrics.isCompactFull ? 62 : 72

        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 8) {
                trackText(
                    player.track.title,
                    font: .system(size: metadataFontSize, weight: .semibold, design: .rounded),
                    foregroundStyle: AnyShapeStyle(.primary),
                    height: titleHeight,
                    alignment: .leading,
                    shadow: TextShadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())

                Text(timePairString(position: scrubPosition, duration: player.track.duration))
                    .font(.system(size: timerFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: timerWidth, alignment: .trailing)
            }

            HStack(alignment: .top, spacing: 8) {
                trackText(
                    player.track.artist,
                    font: .system(size: metadataFontSize, weight: .medium, design: .rounded),
                    foregroundStyle: AnyShapeStyle(.secondary.opacity(0.92)),
                    height: artistHeight,
                    alignment: .leading,
                    shadow: TextShadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())

                Color.clear
                    .frame(width: timerWidth)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: metrics.contentWidth, alignment: .leading)
    }

    private func trackText(
        _ value: String,
        font: Font,
        foregroundStyle: AnyShapeStyle,
        height: CGFloat,
        alignment: Alignment,
        shadow: TextShadow
    ) -> some View {
        StaticTrackText(
            value: value,
            font: font,
            foregroundStyle: foregroundStyle,
            height: height,
            alignment: alignment,
            shadow: shadow
        )
    }

    private func controls(
        buttonScale: ControlButtonScale,
        spacing: CGFloat,
        fillsWidth: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ControlButton(systemName: "backward.fill", size: buttonScale.sideButtonSize, action: player.previousTrack)
            ControlButton(
                systemName: player.track.isPlaying ? "pause.fill" : "play.fill",
                size: buttonScale.playButtonSize,
                action: player.playPause
            )
            ControlButton(systemName: "forward.fill", size: buttonScale.sideButtonSize, action: player.nextTrack)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
    }

    private var progress: some View {
        GlassProgressSlider(
            value: $scrubPosition,
            range: player.track.progressRange,
            isEnabled: player.track.isAvailable && player.track.duration > 0,
            onEditingChanged: { editing in
                isScrubbing = editing
                if !editing {
                    player.seek(to: scrubPosition)
                }
            }
        )
        .accentColor(.green)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let whole = Int(seconds)
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }

    private func timePairString(position: Double, duration: Double) -> String {
        "\(timeString(position))/\(timeString(duration))"
    }

    private func openSpotify() {
        if let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.spotify.client")
            .first {
            runningApp.activate(options: [.activateAllWindows])
            return
        }

        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
            return
        }

        if let spotifyURL = URL(string: "spotify:") {
            NSWorkspace.shared.open(spotifyURL)
        }
    }
}

private struct ResizeCornerMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack(alignment: .bottomTrailing) {
                resizeStroke(inset: 1, side: side)
                resizeStroke(inset: 4, side: side)
            }
        }
        .foregroundStyle(.white.opacity(0.38))
        .shadow(color: .black.opacity(0.20), radius: 0.5, x: 0, y: 0.5)
    }

    private func resizeStroke(inset: CGFloat, side: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: side - inset, y: 3 + inset))
            path.addLine(to: CGPoint(x: 3 + inset, y: side - inset))
        }
        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }
}

private struct PanelInteractionSurface: NSViewRepresentable {
    let mode: OverlayContentMode
    let metrics: OverlayMetrics

    func makeNSView(context: Context) -> PanelInteractionView {
        let view = PanelInteractionView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.mode = mode
        view.metrics = metrics
        return view
    }

    func updateNSView(_ nsView: PanelInteractionView, context: Context) {
        nsView.mode = mode
        nsView.metrics = metrics
    }
}

private final class PanelInteractionView: NSView {
    var mode: OverlayContentMode = .medium
    var metrics = OverlayMetrics(size: OverlaySizeRules.defaultSize)

    private let dragThreshold: CGFloat = 3

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              bounds.contains(point),
              shouldHandleCurrentEvent,
              role(at: point) != .passthrough else {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        let startOrigin = window.frame.origin
        let startMousePoint = NSEvent.mouseLocation
        window.performDrag(with: event)

        let originOffset = NSSize(
            width: window.frame.origin.x - startOrigin.x,
            height: window.frame.origin.y - startOrigin.y
        )
        let mouseOffset = NSSize(
            width: NSEvent.mouseLocation.x - startMousePoint.x,
            height: NSEvent.mouseLocation.y - startMousePoint.y
        )

        if movementDistance(originOffset) > 0.5 || movementDistance(mouseOffset) > dragThreshold {
            OverlayPositionStore.save(origin: window.frame.origin)
            return
        }
    }

    private func movementDistance(_ offset: NSSize) -> CGFloat {
        sqrt((offset.width * offset.width) + (offset.height * offset.height))
    }

    private var shouldHandleCurrentEvent: Bool {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return false
        default:
            return true
        }
    }

    private func role(at point: NSPoint) -> PanelInteractionRole {
        switch mode {
        case .full:
            return bigRole(at: point)
        case .medium:
            return mediumRole(at: point)
        case .small:
            return smallRole(at: point)
        }
    }

    private func bigRole(at point: CGPoint) -> PanelInteractionRole {
        let contentX = metrics.padding + metrics.artworkSide + metrics.columnSpacing
        let contentY = metrics.padding
        let contentWidth = metrics.contentWidth
        let artworkRect = rectFromTop(
            x: metrics.padding,
            topY: metrics.padding,
            width: metrics.artworkSide,
            height: metrics.artworkSide
        )
        let metadataRect = rectFromTop(
            x: contentX,
            topY: contentY,
            width: contentWidth,
            height: 28
        )
        let controlsRect = rectFromTop(
            x: contentX - 4,
            topY: contentY + 30,
            width: 86,
            height: 34
        )
        let progressRect = rectFromTop(
            x: contentX - 2,
            topY: contentY + metrics.artworkSide - 18,
            width: max(1, contentWidth - metrics.progressTrailingReserve) + 4,
            height: 20
        )

        if controlsRect.contains(point) || progressRect.contains(point) {
            return .passthrough
        }

        if artworkRect.contains(point) {
            return .passthrough
        }

        if metadataRect.contains(point) {
            return .dragOnly
        }

        return .dragOnly
    }

    private func mediumRole(at point: CGPoint) -> PanelInteractionRole {
        let contentX = metrics.padding
        let contentHeight = metrics.mediumContentHeight
        let centeredContentOffset = max(0, (metrics.innerHeight - contentHeight) / 2)
        let contentY = metrics.padding + centeredContentOffset
        let controlRowRect = rectFromTop(
            x: contentX - 3,
            topY: contentY + metrics.mediumTitleHeight + metrics.mediumRowGap - 4,
            width: metrics.innerWidth + 6,
            height: metrics.mediumControlRowHeight + 8
        )

        if controlRowRect.contains(point) {
            return .passthrough
        }

        return .dragOnly
    }

    private func smallRole(at point: CGPoint) -> PanelInteractionRole {
        let controlsWidth = (ControlButtonScale.small.sideButtonSize * 2) +
            ControlButtonScale.small.playButtonSize +
            10
        let controlStartX = metrics.padding + max(0, (metrics.innerWidth - controlsWidth) / 2)
        let previousRect = controlButtonRect(
            x: controlStartX,
            side: ControlButtonScale.small.sideButtonSize
        )
        let playRect = controlButtonRect(
            x: controlStartX + ControlButtonScale.small.sideButtonSize + 5,
            side: ControlButtonScale.small.playButtonSize
        )
        let nextRect = controlButtonRect(
            x: controlStartX + ControlButtonScale.small.sideButtonSize + 5 + ControlButtonScale.small.playButtonSize + 5,
            side: ControlButtonScale.small.sideButtonSize
        )

        if previousRect.contains(point) || playRect.contains(point) || nextRect.contains(point) {
            return .passthrough
        }

        return .dragOnly
    }

    private func controlButtonRect(x: CGFloat, side: CGFloat) -> CGRect {
        CGRect(
            x: x - 3,
            y: ((metrics.surfaceHeight - side) / 2) - 3,
            width: side + 6,
            height: side + 6
        )
    }

    private func rectFromTop(
        x: CGFloat,
        topY: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: x,
            y: metrics.surfaceHeight - topY - height,
            width: width,
            height: height
        )
    }
}

private struct PanelResizeSurface: NSViewRepresentable {
    let settings: OverlaySettings

    func makeNSView(context: Context) -> PanelResizeView {
        let view = PanelResizeView(frame: .zero)
        view.settings = settings
        return view
    }

    func updateNSView(_ nsView: PanelResizeView, context: Context) {
        nsView.settings = settings
    }
}

private final class PanelResizeView: NSView {
    weak var settings: OverlaySettings?

    private var startFrame: NSRect?
    private var startMouseLocation: NSPoint?
    private var resizeTrackingArea: NSTrackingArea?

    private static let hoverCursor = NSCursor.openHand
    private static let draggingCursor = NSCursor.closedHand

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              bounds.contains(point),
              shouldHandleCurrentEvent else {
            return nil
        }

        return self
    }

    override func updateTrackingAreas() {
        if let resizeTrackingArea {
            removeTrackingArea(resizeTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .activeAlways,
                .enabledDuringMouseDrag,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate
            ],
            owner: self
        )
        addTrackingArea(trackingArea)
        resizeTrackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: Self.hoverCursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(isDragging: startFrame != nil)
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(isDragging: startFrame != nil)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(isDragging: false)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        updateCursor(isDragging: true)
        startFrame = window?.frame
        startMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        updateCursor(isDragging: true)
        resizeWindow(persist: false)
    }

    override func mouseUp(with event: NSEvent) {
        resizeWindow(persist: true)
        startFrame = nil
        startMouseLocation = nil

        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            updateCursor(isDragging: false)
        } else {
            NSCursor.arrow.set()
        }
    }

    private func updateCursor(isDragging: Bool) {
        if isDragging {
            Self.draggingCursor.set()
        } else {
            Self.hoverCursor.set()
        }
    }

    private var shouldHandleCurrentEvent: Bool {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return false
        default:
            return true
        }
    }

    private func resizeWindow(persist: Bool) {
        guard let window,
              let startFrame,
              let startMouseLocation else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let proposedSize = NSSize(
            width: startFrame.width + currentMouseLocation.x - startMouseLocation.x,
            height: startFrame.height - currentMouseLocation.y + startMouseLocation.y
        )
        let clampedSize = clampedSizeKeepingTopLeftFixed(proposedSize, startFrame: startFrame, window: window)
        let resizedFrame = NSRect(
            x: startFrame.minX,
            y: startFrame.maxY - clampedSize.height,
            width: clampedSize.width,
            height: clampedSize.height
        )

        window.contentView?.frame = NSRect(origin: .zero, size: clampedSize)
        window.setFrame(resizedFrame, display: true, animate: false)
        settings?.setOverlaySize(clampedSize, persist: persist)

        if persist {
            OverlayPositionStore.save(origin: resizedFrame.origin)
        }
    }

    private func clampedSizeKeepingTopLeftFixed(
        _ proposedSize: NSSize,
        startFrame: NSRect,
        window: NSWindow
    ) -> NSSize {
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maximumVisibleSize = NSSize(
            width: max(OverlaySizeRules.minimumSize.width, visibleFrame.maxX - startFrame.minX),
            height: max(OverlaySizeRules.minimumSize.height, startFrame.maxY - visibleFrame.minY)
        )
        let screenClampedSize = NSSize(
            width: min(proposedSize.width, maximumVisibleSize.width),
            height: min(proposedSize.height, maximumVisibleSize.height)
        )

        return OverlaySizeRules.clamped(screenClampedSize)
    }
}

private enum PanelInteractionRole {
    case passthrough
    case dragOnly
}

private struct PanelContentInteraction: ViewModifier {
    let opensSpotifyOnClick: Bool
    let openSpotify: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            PanelContentInteractionSurface(
                opensSpotifyOnClick: opensSpotifyOnClick,
                openSpotify: openSpotify
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PanelContentInteractionSurface: NSViewRepresentable {
    let opensSpotifyOnClick: Bool
    let openSpotify: () -> Void

    func makeNSView(context: Context) -> PanelContentInteractionView {
        let view = PanelContentInteractionView(frame: .zero)
        view.opensSpotifyOnClick = opensSpotifyOnClick
        view.openSpotify = openSpotify
        return view
    }

    func updateNSView(_ nsView: PanelContentInteractionView, context: Context) {
        nsView.opensSpotifyOnClick = opensSpotifyOnClick
        nsView.openSpotify = openSpotify
    }
}

private final class PanelContentInteractionView: NSView {
    var opensSpotifyOnClick = false
    var openSpotify: () -> Void = {}

    private let dragThreshold: CGFloat = 3

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              bounds.contains(point),
              shouldHandleCurrentEvent else {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            if opensSpotifyOnClick {
                openSpotify()
            }
            return
        }

        let startOrigin = window.frame.origin
        let startMousePoint = NSEvent.mouseLocation
        window.performDrag(with: event)

        let originOffset = NSSize(
            width: window.frame.origin.x - startOrigin.x,
            height: window.frame.origin.y - startOrigin.y
        )
        let mouseOffset = NSSize(
            width: NSEvent.mouseLocation.x - startMousePoint.x,
            height: NSEvent.mouseLocation.y - startMousePoint.y
        )

        if movementDistance(originOffset) > 0.5 || movementDistance(mouseOffset) > dragThreshold {
            OverlayPositionStore.save(origin: window.frame.origin)
            return
        }

        if opensSpotifyOnClick {
            openSpotify()
        }
    }

    private var shouldHandleCurrentEvent: Bool {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return false
        default:
            return true
        }
    }

    private func movementDistance(_ offset: NSSize) -> CGFloat {
        sqrt((offset.width * offset.width) + (offset.height * offset.height))
    }
}

private struct TextShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

private struct StaticTrackText: View {
    let value: String
    let font: Font
    let foregroundStyle: AnyShapeStyle
    let height: CGFloat
    let alignment: Alignment
    let shadow: TextShadow

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0

    private let trailingFadeWidth: CGFloat = 18

    private var shouldFadeTail: Bool {
        textWidth > containerWidth + 1
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width, 1)

            textContent(availableWidth: availableWidth)
                .onAppear {
                    containerWidth = availableWidth
                }
                .onChange(of: proxy.size.width) { width in
                    containerWidth = max(width, 1)
                }
        }
        .frame(height: height)
        .background(textWidthReader)
    }

    @ViewBuilder
    private func textContent(availableWidth: CGFloat) -> some View {
        let text = Text(value)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)

        if shouldFadeTail {
            text
                .frame(width: max(textWidth, availableWidth), height: height, alignment: .leading)
                .frame(width: availableWidth, height: height, alignment: .leading)
                .clipped()
                .mask(textMask)
        } else {
            text
                .frame(width: availableWidth, height: height, alignment: alignment)
                .clipped()
        }
    }

    private var textWidthReader: some View {
        Text(value)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: StaticTrackTextWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
                }
            )
            .hidden()
            .onPreferenceChange(StaticTrackTextWidthPreferenceKey.self) { width in
                textWidth = max(width, 0)
            }
    }

    @ViewBuilder
    private var textMask: some View {
        if shouldFadeTail {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.black)
                    .frame(width: max(containerWidth - trailingFadeWidth, 0))

                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: trailingFadeWidth)
            }
            .frame(width: max(containerWidth, 1), height: height, alignment: .leading)
        } else {
            Rectangle()
                .fill(.black)
                .frame(width: max(containerWidth, 1), height: height)
        }
    }
}

private struct StaticTrackTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func panelDragInteraction() -> some View {
        modifier(
            PanelContentInteraction(
                opensSpotifyOnClick: false,
                openSpotify: {}
            )
        )
    }

    func panelArtworkInteraction(openSpotify: @escaping () -> Void) -> some View {
        modifier(
            PanelContentInteraction(
                opensSpotifyOnClick: true,
                openSpotify: openSpotify
            )
        )
    }
}

private struct ControlButtonScale {
    let sideButtonSize: CGFloat
    let playButtonSize: CGFloat

    static let regular = ControlButtonScale(sideButtonSize: 20, playButtonSize: 25)
    static let medium = ControlButtonScale(sideButtonSize: 21, playButtonSize: 26)
    static let small = ControlButtonScale(sideButtonSize: 18, playButtonSize: 23)
    static let micro = ControlButtonScale(sideButtonSize: 16, playButtonSize: 20)

    func width(spacing: CGFloat) -> CGFloat {
        (sideButtonSize * 2) + playButtonSize + (spacing * 2)
    }
}

private struct ArtworkView: View {
    let image: NSImage?
    let isAvailable: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.thinMaterial)
                .opacity(0.48)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: isAvailable ? "music.note" : "sparkle.magnifyingglass")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blendMode(.screen)
        }
    }
}

private struct ControlButton: View {
    let systemName: String
    var size: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: systemName)
                    .font(.system(size: symbolSize, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: symbolCanvasSize, height: symbolCanvasSize, alignment: .center)
                    .offset(x: symbolOffset.width, y: symbolOffset.height)
            }
            .frame(width: size, height: size, alignment: .center)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size, alignment: .center)
        .foregroundStyle(.primary)
        .background(.thinMaterial, in: Circle())
        .background(Color.black.opacity(0.08), in: Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
        }
        .overlay {
            Circle()
                .strokeBorder(Color.black.opacity(0.16), lineWidth: 0.5)
                .padding(0.5)
        }
    }

    private var symbolSize: CGFloat {
        switch systemName {
        case "play.fill", "pause.fill":
            return min(9.0, max(8.1, size * 0.35))
        default:
            return min(8.2, max(7.4, size * 0.39))
        }
    }

    private var symbolCanvasSize: CGFloat {
        symbolSize + 4
    }

    private var symbolOffset: CGSize {
        let scale = size / ControlButtonScale.small.playButtonSize

        switch systemName {
        case "backward.fill":
            return CGSize(width: -0.35 * scale, height: 0)
        case "forward.fill":
            return CGSize(width: 0.35 * scale, height: 0)
        case "play.fill":
            return CGSize(width: 0.52 * scale, height: 0)
        case "pause.fill":
            return CGSize(width: 0.05 * scale, height: 0)
        default:
            return .zero
        }
    }
}

private struct GlassProgressSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isEnabled: Bool
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = normalizedFraction
            let thumbSize: CGFloat = isDragging ? 10 : 9
            let trackHeight: CGFloat = 2
            let hitHeight: CGFloat = 18
            let thumbOffset = max(0, min(width - thumbSize, (width - thumbSize) * fraction))
            let fillWidth = max(trackHeight, thumbOffset + (thumbSize / 2))
            let trackOpacity = isEnabled ? 1.0 : 0.45

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.62))
                    .opacity(trackOpacity)
                    .frame(width: width, height: trackHeight)

                Capsule()
                    .fill(Color.green.opacity(0.86))
                    .opacity(trackOpacity)
                    .frame(width: min(width, fillWidth), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 0.5)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbOffset)
            }
            .frame(width: width, height: hitHeight, alignment: .center)
            .contentShape(Rectangle())
            .overlay {
                SeekInteractionSurface(
                    value: $value,
                    isDragging: $isDragging,
                    range: range,
                    isEnabled: isEnabled,
                    onEditingChanged: onEditingChanged
                )
                .frame(width: width, height: hitHeight)
            }
        }
        .frame(height: 18)
    }

    private var normalizedFraction: Double {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return 0 }
        let clamped = max(range.lowerBound, min(value, range.upperBound))
        return (clamped - range.lowerBound) / distance
    }

}

private struct SeekInteractionSurface: NSViewRepresentable {
    @Binding var value: Double
    @Binding var isDragging: Bool
    let range: ClosedRange<Double>
    let isEnabled: Bool
    let onEditingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> SeekInteractionView {
        let view = SeekInteractionView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ nsView: SeekInteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: SeekInteractionView) {
        view.value = $value
        view.isDragging = $isDragging
        view.range = range
        view.isEnabled = isEnabled
        view.onEditingChanged = onEditingChanged
    }
}

private final class SeekInteractionView: NSView {
    var value: Binding<Double> = .constant(0)
    var isDragging: Binding<Bool> = .constant(false)
    var range: ClosedRange<Double> = 0...1
    var isEnabled = true
    var onEditingChanged: (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled,
              !isHidden,
              bounds.contains(point) else {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        beginSeeking()
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateValue(with: event)
        endSeeking()
    }

    private func beginSeeking() {
        guard !isDragging.wrappedValue else {
            return
        }

        isDragging.wrappedValue = true
        onEditingChanged(true)
    }

    private func endSeeking() {
        guard isDragging.wrappedValue else {
            return
        }

        isDragging.wrappedValue = false
        onEditingChanged(false)
    }

    private func updateValue(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        updateValue(locationX: location.x, width: bounds.width)
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        guard range.upperBound > range.lowerBound else {
            return
        }

        let fraction = max(0, min(1, Double(locationX / max(width, 1))))
        value.wrappedValue = range.lowerBound + ((range.upperBound - range.lowerBound) * fraction)
    }
}

private struct GlassPanel: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 3)
    }
}
