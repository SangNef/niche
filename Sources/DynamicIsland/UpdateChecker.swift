import AppKit
import Combine

struct AppUpdateInfo: Equatable {
    let version: String
    let url: URL
}

/// Checks GitHub Releases once at launch (and again periodically while the app
/// keeps running in the background) for a newer tagged release than the running
/// build, and surfaces it as a transient notch HUD the user can click to open the
/// release page. No auto-download/install: the app isn't notarized, so a silently
/// installed update would just get blocked by Gatekeeper on next launch anyway —
/// simplest to let the user grab the new .dmg themselves.
final class UpdateChecker: ObservableObject {
    @Published private(set) var available: AppUpdateInfo?
    @Published private(set) var isVisible = false

    private static let repo = "SangNef/niche"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private var hideWorkItem: DispatchWorkItem?
    private var timer: Timer?

    init() {
        checkForUpdate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdate()
        }
    }

    deinit { timer?.invalidate() }

    func openReleasePage() {
        guard let url = available?.url else { return }
        NSWorkspace.shared.open(url)
        dismiss()
    }

    func dismiss() {
        hideWorkItem?.cancel()
        isVisible = false
    }

    private func checkForUpdate() {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString)
            else { return }

            let latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  Self.isNewer(latestVersion, than: currentVersion)
            else { return }

            DispatchQueue.main.async {
                self?.show(AppUpdateInfo(version: latestVersion, url: htmlURL))
            }
        }.resume()
    }

    private func show(_ info: AppUpdateInfo) {
        // Don't re-flash the HUD for a version we already told the user about in this run.
        guard available?.version != info.version else { return }
        available = info
        isVisible = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.isVisible = false }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(candidateParts.count, currentParts.count)
        for i in 0..<count {
            let c = i < candidateParts.count ? candidateParts[i] : 0
            let r = i < currentParts.count ? currentParts[i] : 0
            if c != r { return c > r }
        }
        return false
    }
}
