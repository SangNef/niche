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
