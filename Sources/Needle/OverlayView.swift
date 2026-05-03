import AppKit
import SwiftUI

enum OverlayLayout: String, CaseIterable {
    case big
    case medium
    case small

    var title: String {
        switch self {
        case .big:
            return "Big"
        case .medium:
            return "Medium"
        case .small:
            return "Small"
        }
    }

    var metrics: OverlayMetrics {
        switch self {
        case .big:
            return OverlayMetrics(
                surfaceWidth: 316,
                surfaceHeight: 90,
                shadowMargin: 8,
                padding: 10,
                artworkSide: 70,
                columnSpacing: 10,
                cornerRadius: 18
            )
        case .medium:
            return OverlayMetrics(
                surfaceWidth: 242,
                surfaceHeight: 64,
                shadowMargin: 8,
                padding: 9,
                artworkSide: 0,
                columnSpacing: 0,
                cornerRadius: 17
            )
        case .small:
            return OverlayMetrics(
                surfaceWidth: 92,
                surfaceHeight: 36,
                shadowMargin: 6,
                padding: 6,
                artworkSide: 0,
                columnSpacing: 0,
                cornerRadius: 16
            )
        }
    }
}

struct OverlayMetrics {
    let surfaceWidth: CGFloat
    let surfaceHeight: CGFloat
    let shadowMargin: CGFloat
    let padding: CGFloat
    let artworkSide: CGFloat
    let columnSpacing: CGFloat
    let cornerRadius: CGFloat

    var width: CGFloat {
        surfaceWidth + (shadowMargin * 2)
    }

    var height: CGFloat {
        surfaceHeight + (shadowMargin * 2)
    }

    var contentWidth: CGFloat {
        surfaceWidth - (padding * 2) - artworkSide - columnSpacing
    }

    var innerWidth: CGFloat {
        surfaceWidth - (padding * 2)
    }

    var innerHeight: CGFloat {
        surfaceHeight - (padding * 2)
    }
}

final class OverlaySettings: ObservableObject {
    @Published var layout: OverlayLayout {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
        }
    }

    private static let layoutKey = "Needle.overlayLayout"

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: Self.layoutKey),
           let savedLayout = OverlayLayout(rawValue: rawValue) {
            layout = savedLayout
        } else {
            layout = .big
        }
    }
}

struct OverlayView: View {
    @ObservedObject var player: SpotifyPlayer
    @ObservedObject var settings: OverlaySettings
    @StateObject private var artwork = ArtworkLoader()
    @State private var scrubPosition: Double = 0
    @State private var volumePosition: Double = 50
    @State private var isScrubbing = false
    @State private var isVolumeScrubbing = false

    var body: some View {
        let metrics = settings.layout.metrics

        ZStack {
            layoutContent(for: settings.layout, metrics: metrics)
            .padding(metrics.padding)
            .frame(width: metrics.surfaceWidth, height: metrics.surfaceHeight)
            .background(GlassPanel(cornerRadius: metrics.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        }
        .frame(width: metrics.width, height: metrics.height)
        .contextMenu {
            Button("Big Layout") {
                settings.layout = .big
            }
            Button("Medium Layout") {
                settings.layout = .medium
            }
            Button("Small Layout") {
                settings.layout = .small
            }
            Divider()
            Button("Quit Needle") {
                NSApp.terminate(nil)
            }
        }
        .onAppear {
            artwork.load(player.track.artworkURL)
            scrubPosition = player.track.position
            volumePosition = player.track.volume
        }
        .onChange(of: player.track) { track in
            artwork.load(track.artworkURL)
            if !isScrubbing {
                scrubPosition = track.position
            }
            if !isVolumeScrubbing {
                volumePosition = track.volume
            }
        }
    }

    @ViewBuilder
    private func layoutContent(for layout: OverlayLayout, metrics: OverlayMetrics) -> some View {
        switch layout {
        case .big:
            bigLayout(metrics: metrics)
        case .medium:
            mediumLayout(metrics: metrics)
        case .small:
            smallLayout
        }
    }

    private func bigLayout(metrics: OverlayMetrics) -> some View {
        HStack(alignment: .top, spacing: metrics.columnSpacing) {
            ArtworkView(image: artwork.image, isAvailable: player.track.isAvailable)
                .frame(width: metrics.artworkSide, height: metrics.artworkSide)

            VStack(alignment: .leading, spacing: 0) {
                trackInfo
                    .frame(width: metrics.contentWidth, alignment: .leading)

                Spacer(minLength: 4)

                HStack(alignment: .bottom, spacing: 8) {
                    controls(
                        buttonScale: .regular,
                        spacing: 6,
                        fillsWidth: false
                    )

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 3) {
                        volumeControl
                            .frame(width: 62, alignment: .trailing)

                        Text(timePairString(position: scrubPosition, duration: player.track.duration))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                .frame(width: metrics.contentWidth, alignment: .leading)

                Spacer(minLength: 2)

                progress
                    .frame(width: metrics.contentWidth, height: 13, alignment: .bottom)
                    .padding(.bottom, 4)
            }
            .frame(width: metrics.contentWidth, height: metrics.artworkSide, alignment: .top)
        }
        .frame(width: metrics.innerWidth, height: metrics.innerHeight, alignment: .topLeading)
    }

    private func mediumLayout(metrics: OverlayMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(player.track.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.40), radius: 2, x: 0, y: 1)

                Text(player.track.artist)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 82, alignment: .trailing)
                    .shadow(color: .black.opacity(0.30), radius: 2, x: 0, y: 1)
            }
            .frame(width: metrics.innerWidth, alignment: .leading)

            Spacer(minLength: 5)

            HStack(alignment: .center, spacing: 9) {
                controls(
                    buttonScale: .medium,
                    spacing: 6,
                    fillsWidth: false
                )
                    .frame(width: 82, alignment: .leading)

                progress
                    .frame(height: 13, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: metrics.innerWidth, alignment: .center)
        }
        .frame(width: metrics.innerWidth, height: metrics.innerHeight, alignment: .topLeading)
    }

    private var smallLayout: some View {
        controls(buttonScale: .small, spacing: 5, fillsWidth: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(player.track.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

            Text(player.track.artist)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var volumeControl: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: volumePosition <= 1 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)

            MiniGlassSlider(
                value: $volumePosition,
                range: player.track.volumeRange,
                fill: .white.opacity(0.58),
                onEditingChanged: { editing in
                    isVolumeScrubbing = editing
                    if !editing {
                        player.setVolume(to: volumePosition)
                    }
                }
            )
        }
        .frame(height: 13, alignment: .center)
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
}

private struct ControlButtonScale {
    let sideButtonSize: CGFloat
    let playButtonSize: CGFloat

    static let regular = ControlButtonScale(sideButtonSize: 20, playButtonSize: 25)
    static let medium = ControlButtonScale(sideButtonSize: 21, playButtonSize: 26)
    static let small = ControlButtonScale(sideButtonSize: 18, playButtonSize: 23)
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
                    .frame(width: symbolSize + 2, height: symbolSize + 2, alignment: .center)
            }
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.thinMaterial, in: Circle())
        .background(Color.white.opacity(0.04), in: Circle())
    }

    private var symbolSize: CGFloat {
        if size >= 25 {
            return 9
        }

        if size >= 22 {
            return 8.5
        }

        return 7.5
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
            let thumbSize: CGFloat = isDragging ? 15 : 13
            let trackHeight: CGFloat = 7

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .frame(height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.60), .green.opacity(0.58)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumbSize / 2, width * fraction), height: trackHeight)

                Circle()
                    .fill(.regularMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.34), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: max(0, min(width - thumbSize, (width - thumbSize) * fraction)))
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .allowsHitTesting(isEnabled)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        updateValue(locationX: gesture.location.x, width: width)
                    }
                    .onEnded { gesture in
                        updateValue(locationX: gesture.location.x, width: width)
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 13)
    }

    private var normalizedFraction: Double {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return 0 }
        let clamped = max(range.lowerBound, min(value, range.upperBound))
        return (clamped - range.lowerBound) / distance
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let fraction = max(0, min(1, Double(locationX / max(width, 1))))
        value = range.lowerBound + ((range.upperBound - range.lowerBound) * fraction)
    }
}

private struct MiniGlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let fill: Color
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fraction = normalizedFraction
            let thumbSize: CGFloat = isDragging ? 8 : 7
            let trackHeight: CGFloat = 4

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(fill)
                    .frame(width: max(thumbSize / 2, width * fraction), height: trackHeight)

                Circle()
                    .fill(.regularMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.26), lineWidth: 1)
                    }
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: max(0, min(width - thumbSize, (width - thumbSize) * fraction)))
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        updateValue(locationX: gesture.location.x, width: width)
                    }
                    .onEnded { gesture in
                        updateValue(locationX: gesture.location.x, width: width)
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 8)
    }

    private var normalizedFraction: Double {
        let distance = range.upperBound - range.lowerBound
        guard distance > 0 else { return 0 }
        let clamped = max(range.lowerBound, min(value, range.upperBound))
        return (clamped - range.lowerBound) / distance
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let fraction = max(0, min(1, Double(locationX / max(width, 1))))
        value = range.lowerBound + ((range.upperBound - range.lowerBound) * fraction)
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
