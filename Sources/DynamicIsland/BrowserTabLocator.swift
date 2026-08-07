import Foundation

/// Best-effort "jump to the exact browser tab that's playing" for the handful of
/// scriptable browsers. There's no public API for this — mediaremote-adapter gives
/// us a title/artist but never a tab URL — so this shells out to AppleScript to
/// search open tabs by title match. Doesn't work for Firefox (no AppleScript/JXA tab
/// scripting at all) or any browser without a compatible "tabs" dictionary.
enum BrowserTabLocator {
    private static let safariBundleID = "com.apple.Safari"
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    static func isSupported(bundleIdentifier: String) -> Bool {
        bundleIdentifier == safariBundleID || chromiumBundleIDs.contains(bundleIdentifier)
    }

    /// Tries to activate the tab at `url`. Returns false if no open tab currently has
    /// that URL (closed, navigated away, etc.) so the caller can fall back.
    static func activateTab(url: String, bundleIdentifier: String) -> Bool {
        guard let script = script(bundleIdentifier: bundleIdentifier, matching: .url(url)) else {
            return false
        }
        return run(script) == "ok"
    }

    /// Searches open tabs for one whose title contains `titleContains`, activates it,
    /// and returns its URL for caching. Best-effort substring match — there's no
    /// exact identifier linking a Now Playing entry to a specific tab.
    static func findAndActivateTab(titleContains: String, bundleIdentifier: String) -> String? {
        guard let script = script(bundleIdentifier: bundleIdentifier, matching: .titleContains(titleContains)) else {
            return nil
        }
        let result = run(script)
        return (result?.isEmpty == false) ? result : nil
    }

    private enum Matcher {
        case url(String)
        case titleContains(String)
    }

    private static func script(bundleIdentifier: String, matching matcher: Matcher) -> String? {
        let isSafari = bundleIdentifier == safariBundleID
        guard isSafari || chromiumBundleIDs.contains(bundleIdentifier) else { return nil }

        let condition: String
        let successReturn: String
        switch matcher {
        case .url(let url):
            condition = "URL of t is \"\(escape(url))\""
            successReturn = "\"ok\""
        case .titleContains(let text):
            let titleProperty = isSafari ? "name" : "title"
            condition = "\(titleProperty) of t contains \"\(escape(text))\""
            successReturn = "URL of t"
        }

        // Safari addresses the tab to switch to directly; Chromium browsers use a
        // 1-based active-tab index within the window instead.
        let activateTab = isSafari
            ? "set current tab of w to t"
            : "set active tab index of w to tabIndex"

        return """
        tell application id "\(bundleIdentifier)"
            repeat with w in windows
                set tabIndex to 0
                repeat with t in tabs of w
                    set tabIndex to tabIndex + 1
                    if \(condition) then
                        \(activateTab)
                        set index of w to 1
                        activate
                        return \(successReturn)
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Runs synchronously (AppleEvent round-trip to the browser) — callers must not
    /// invoke this on the main thread.
    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict {
            print("[BrowserTab] AppleScript error: \(errorDict)")
            return nil
        }
        return result.stringValue
    }
}
