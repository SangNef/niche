import AppKit
import SwiftUI

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var artwork: NSImage?
    var artworkIdentifier: String?
    var accentColor: Color
    var duration: Double
    var elapsedTime: Double
    var playbackRate: Double
    var timestamp: Date

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
            && lhs.duration == rhs.duration && lhs.elapsedTime == rhs.elapsedTime
            && lhs.artworkIdentifier == rhs.artworkIdentifier
    }

    /// Interpolates playback position between adapter updates so the progress bar
    /// can tick every second locally instead of waiting for the next stream event.
    func liveElapsed(at date: Date = Date()) -> Double {
        guard isPlaying, duration > 0 else { return min(elapsedTime, duration) }
        let projected = elapsedTime + date.timeIntervalSince(timestamp) * playbackRate
        return min(max(projected, 0), duration)
    }
}

/// Reads the system-wide "Now Playing" info (Music.app, Spotify, browser tabs, ...)
/// by streaming JSON from the bundled `mediaremote-adapter` helper. Direct calls to
/// MediaRemote.framework stopped working for third-party processes on macOS 15.4+;
/// the helper works around that by running through /usr/bin/perl, which macOS still
/// grants MediaRemote access. See vendor/mediaremote-adapter (github.com/ungive/mediaremote-adapter).
final class NowPlayingProvider: ObservableObject {
    @Published private(set) var current: NowPlayingInfo?

    private var process: Process?
    private var buffer = Data()
    private static let dateFormatter = ISO8601DateFormatter()

    private var lastTrackKey: String?
    private var lastArtworkBase64: String?
    private var cachedArtwork: NSImage?
    private var cachedAccentColor = Color.white.opacity(0.5)

    init() {
        start()
    }

    deinit { process?.terminate() }

    private func start() {
        guard let paths = MediaRemoteAdapterPaths.resolve() else {
            print("[NowPlaying] mediaremote-adapter script/framework not found; now-playing disabled")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework, "stream", "--no-diff"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handle(handle.availableData)
        }

        do {
            try process.run()
            self.process = process
        } catch {
            print("[NowPlaying] failed to launch adapter: \(error)")
        }
    }

    private func handle(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            parse(Data(lineData))
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
        }
    }

    private func parse(_ lineData: Data) {
        guard !lineData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else { return }

        let title = payload["title"] as? String
        let artist = payload["artist"] as? String
        let isPlaying = payload["playing"] as? Bool ?? false
        let duration = payload["duration"] as? Double ?? 0
        let elapsedTime = payload["elapsedTime"] as? Double ?? 0
        let playbackRate = payload["playbackRate"] as? Double ?? (isPlaying ? 1 : 0)
        let timestamp = (payload["timestamp"] as? String)
            .flatMap { Self.dateFormatter.date(from: $0) } ?? Date()

        var newValue: NowPlayingInfo?
        if let title, !title.isEmpty {
            // A new track (different title/artist) invalidates any cached artwork —
            // otherwise a tick that arrives before the new artwork does would keep
            // showing the previous track's image under the new title.
            let trackKey = "\(title)||\(artist ?? "")"
            if trackKey != lastTrackKey {
                lastTrackKey = trackKey
                lastArtworkBase64 = nil
                cachedArtwork = nil
            }

            if let base64 = payload["artworkData"] as? String, !base64.isEmpty {
                if base64 == lastArtworkBase64, cachedArtwork != nil {
                    // already cached, nothing to do
                } else if let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
                    lastArtworkBase64 = base64
                    cachedArtwork = image
                    if let averageColor = image.averageColor() {
                        cachedAccentColor = Color(nsColor: averageColor.vibrant())
                    }
                }
            }

            newValue = NowPlayingInfo(
                title: title,
                artist: artist ?? "",
                isPlaying: isPlaying,
                artwork: cachedArtwork,
                artworkIdentifier: lastArtworkBase64,
                accentColor: cachedAccentColor,
                duration: duration,
                elapsedTime: elapsedTime,
                playbackRate: playbackRate,
                timestamp: timestamp
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if newValue != self.current { self.current = newValue }
        }
    }

}
