import AppKit
import Foundation

/// Sends playback commands to the currently playing app via the bundled
/// mediaremote-adapter helper (`send COMMAND`). Command IDs per its README.
enum MediaController {
    private static let togglePlayPauseCommand = "2"
    private static let nextTrackCommand = "4"
    private static let previousTrackCommand = "5"

    static func togglePlayPause() { send(togglePlayPauseCommand) }
    static func next() { send(nextTrackCommand) }
    static func previous() { send(previousTrackCommand) }

    /// Brings the app currently reporting Now Playing info to the foreground —
    /// Music, Spotify, or whichever browser has the tab playing. Launches it first
    /// if it's not already running (matches how Control Center's Now Playing tile
    /// behaves when clicked).
    static func openSource(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func send(_ command: String) {
        guard let paths = MediaRemoteAdapterPaths.resolve() else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework, "send", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
