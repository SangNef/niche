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
    /// The playing app's bundle identifier (e.g. "com.spotify.client",
    /// "com.apple.Music", or a browser's if it's playing a tab) — always present
    /// per the adapter's payload contract. Used to bring that app forward on tap.
    var sourceBundleIdentifier: String?

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
    /// True while a track is playing, or briefly after it pauses — lets the compact
    /// pill linger for a grace period before the notch collapses back to idle.
    @Published private(set) var isVisible = false

    private let settings: AppSettings
    private var process: Process?
    private var buffer = Data()
    private static let dateFormatter = ISO8601DateFormatter()
    private static let tabCacheExpiryDelay: TimeInterval = 5 * 60

    private var hideWorkItem: DispatchWorkItem?
    private var tabCacheExpiryWorkItem: DispatchWorkItem?

    /// Track key -> matched browser tab URL (see BrowserTabLocator), so a repeat tap
    /// on the same track doesn't need to re-search open tabs. Cleared a few minutes
    /// after the pill goes idle so it doesn't hold onto stale tab references.
    private var tabURLCache: [String: String] = [:]

    private var lastTrackKey: String?
    private var lastArtworkBase64: String?
    private var cachedArtwork: NSImage?
    private var cachedAccentColor = Color.white.opacity(0.5)

    init(settings: AppSettings) {
        self.settings = settings
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
                timestamp: timestamp,
                sourceBundleIdentifier: payload["bundleIdentifier"] as? String
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard newValue != self.current else { return }
            self.current = newValue
            self.updateVisibility(for: newValue)
        }
    }

    private func updateVisibility(for value: NowPlayingInfo?) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let value else {
            setHidden()
            return
        }

        isVisible = true
        tabCacheExpiryWorkItem?.cancel()
        tabCacheExpiryWorkItem = nil
        guard !value.isPlaying else { return }

        // Paused: keep showing the pill for a grace period, then collapse the notch
        // back to idle if the user hasn't resumed playback by then.
        let workItem = DispatchWorkItem { [weak self] in self?.setHidden() }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.pauseHideDelay, execute: workItem)
    }

    /// Marks the pill hidden and, after a few minutes of staying that way, drops the
    /// cached browser-tab URLs — otherwise they'd just accumulate for tracks long
    /// since stopped, pointing at tabs that may no longer even exist.
    private func setHidden() {
        isVisible = false

        tabCacheExpiryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.tabURLCache.removeAll() }
        tabCacheExpiryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tabCacheExpiryDelay, execute: workItem)
    }

    /// Brings the app that's actually playing to the foreground — Music, Spotify, or
    /// (best-effort, see BrowserTabLocator) the exact browser tab if the source is a
    /// scriptable browser AND Preferences' "Mở đúng tab trình duyệt" toggle is on.
    /// That toggle is what triggers the browser's Automation permission prompt, not
    /// tapping the pill, so nothing is asked for until the user opts in. Falls back
    /// to just activating the app when the toggle is off, the tab can't be found, or
    /// the browser isn't scriptable.
    func openSource(for track: NowPlayingInfo) {
        guard let bundleIdentifier = track.sourceBundleIdentifier else { return }
        guard settings.browserTabJumpEnabled, BrowserTabLocator.isSupported(bundleIdentifier: bundleIdentifier) else {
            MediaController.openSource(bundleIdentifier: bundleIdentifier)
            return
        }

        let key = "\(bundleIdentifier)||\(track.title)||\(track.artist)"
        let cachedURL = tabURLCache[key]
        let title = track.title

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let cachedURL, BrowserTabLocator.activateTab(url: cachedURL, bundleIdentifier: bundleIdentifier) {
                return
            }
            if let url = BrowserTabLocator.findAndActivateTab(titleContains: title, bundleIdentifier: bundleIdentifier) {
                DispatchQueue.main.async { self?.tabURLCache[key] = url }
                return
            }
            MediaController.openSource(bundleIdentifier: bundleIdentifier)
        }
    }

}
