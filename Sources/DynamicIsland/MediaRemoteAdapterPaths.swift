import Foundation

/// Locates the bundled mediaremote-adapter helper (perl script + framework),
/// shared by NowPlayingProvider (reads state) and MediaController (sends commands).
enum MediaRemoteAdapterPaths {
    static func resolve() -> (script: String, framework: String)? {
        let fm = FileManager.default

        // Real .app bundle layout (see Scripts/build_app.sh)
        if let resourceURL = Bundle.main.resourceURL {
            let script = resourceURL.appendingPathComponent("mediaremote-adapter.pl").path
            let framework = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework").path
            if fm.fileExists(atPath: script), fm.fileExists(atPath: framework) {
                return (script, framework)
            }
        }

        // `swift run` dev fallback: package root/vendor/mediaremote-adapter
        let devRoot = fm.currentDirectoryPath + "/vendor/mediaremote-adapter"
        let devScript = devRoot + "/bin/mediaremote-adapter.pl"
        let devFramework = devRoot + "/build/MediaRemoteAdapter.framework"
        if fm.fileExists(atPath: devScript), fm.fileExists(atPath: devFramework) {
            return (devScript, devFramework)
        }

        return nil
    }
}
