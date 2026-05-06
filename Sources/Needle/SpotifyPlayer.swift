import AppKit
import Combine
import Foundation

struct TrackState: Equatable {
    var title: String = "Open Spotify"
    var artist: String = "Needle is waiting"
    var album: String = ""
    var artworkURL: URL?
    var duration: Double = 0
    var position: Double = 0
    var volume: Double = 50
    var isPlaying: Bool = false
    var isAvailable: Bool = false

    var progressRange: ClosedRange<Double> {
        0...max(duration, 1)
    }

    var volumeRange: ClosedRange<Double> {
        0...100
    }
}

final class SpotifyPlayer: ObservableObject {
    @Published private(set) var track = TrackState()

    var trackPublisher: Published<TrackState>.Publisher {
        $track
    }

    private var timer: Timer?
    private let runner = AppleScriptRunner()

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        runner.readTrack { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                self.track = state
            }
        }
    }

    func playPause() {
        runner.run(command: "playpause")
        refreshSoon()
    }

    func nextTrack() {
        runner.run(command: "next track")
        refreshSoon()
    }

    func previousTrack() {
        runner.run(command: "previous track")
        refreshSoon()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, track.duration))
        runner.run(command: "set player position to \(clamped)")
        refreshSoon()
    }

    func setVolume(to volume: Double) {
        let clamped = Int(max(0, min(volume, 100)).rounded())
        runner.run(command: "set sound volume to \(clamped)")
        DispatchQueue.main.async {
            self.track.volume = Double(clamped)
        }
        refreshSoon()
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }
}

private final class AppleScriptRunner {
    private let queue = DispatchQueue(label: "Needle.SpotifyAppleScript", qos: .userInitiated)

    func readTrack(completion: @escaping (TrackState) -> Void) {
        queue.async {
            completion(Self.parse(Self.execute(Self.trackScript)))
        }
    }

    func run(command: String) {
        queue.async {
            _ = Self.execute("""
            if application "Spotify" is running then
                tell application "Spotify" to \(command)
            end if
            """)
        }
    }

    private static func execute(_ source: String) -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return "" }
        let descriptor = script.executeAndReturnError(&error)
        if error != nil {
            return ""
        }
        return descriptor.stringValue ?? ""
    }

    private static func parse(_ value: String) -> TrackState {
        if value == "not_running" || value.isEmpty {
            return TrackState()
        }

        if value.hasPrefix("stopped") {
            let parts = value.components(separatedBy: "\n")
            let volume = parts.count > 1 ? Double(parts[1]) ?? 50 : 50
            return TrackState(
                title: "Spotify paused",
                artist: "Pick a track to wake Needle",
                album: "",
                artworkURL: nil,
                duration: 0,
                position: 0,
                volume: volume,
                isPlaying: false,
                isAvailable: false
            )
        }

        let parts = value.components(separatedBy: "\n")
        guard parts.count >= 8 else {
            return TrackState()
        }

        let durationMS = Double(parts[4]) ?? 0
        let position = Double(parts[5]) ?? 0
        let volume = Double(parts[7]) ?? 50

        return TrackState(
            title: parts[0],
            artist: firstArtist(from: parts[1]),
            album: parts[2],
            artworkURL: URL(string: parts[3]),
            duration: durationMS / 1000,
            position: position,
            volume: volume,
            isPlaying: parts[6] == "true",
            isAvailable: true
        )
    }

    private static func firstArtist(from value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return value
        }

        for separator in [" feat. ", " ft. ", " featuring ", " with ", " x ", ";"] {
            if let range = trimmedValue.range(of: separator, options: [.caseInsensitive]) {
                return String(trimmedValue[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let range = trimmedValue.range(of: ", "),
           shouldSplitCommaArtist(trimmedValue, after: range.upperBound) {
            return String(trimmedValue[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmedValue
    }

    private static func shouldSplitCommaArtist(_ value: String, after index: String.Index) -> Bool {
        let remainder = value[index...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else {
            return false
        }

        let protectedSingleArtistPrefixes = [
            "the creator",
            "the machine",
            "wind",
            "wind & fire"
        ]
        let normalizedRemainder = remainder.lowercased()
        if protectedSingleArtistPrefixes.contains(where: { normalizedRemainder.hasPrefix($0) }) {
            return false
        }

        return true
    }

    private static let trackScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            set trackVolume to sound volume
            if player state is stopped then
                return "stopped" & linefeed & (trackVolume as string)
            end if

            set activeTrack to current track
            set trackName to name of activeTrack
            set trackArtist to artist of activeTrack
            set trackAlbum to album of activeTrack
            set trackArtwork to artwork url of activeTrack
            set trackDuration to duration of activeTrack
            set trackPosition to player position
            set trackPlaying to player state is playing

            return trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & trackArtwork & linefeed & (trackDuration as string) & linefeed & (trackPosition as string) & linefeed & (trackPlaying as string) & linefeed & (trackVolume as string)
        end tell
    else
        return "not_running"
    end if
    """
}
