import SwiftUI

/// The app's Preferences window: a `NavigationSplitView` with a native-style
/// sidebar and a detail pane assembled from the reusable `Preference*`
/// components in `Preferences/`.
struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker

    enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
        case general, notifications, appearance, behavior, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .notifications: "Notifications"
            case .appearance: "Appearance"
            case .behavior: "Behavior"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .notifications: "bell.badge"
            case .appearance: "paintbrush"
            case .behavior: "hand.tap"
            case .about: "info.circle"
            }
        }
    }

    @State private var selection: SettingsSection = .general
    @State private var manualCheckResult: UpdateCheckResult?
    @State private var showUpdateAlert = false

    var body: some View {
        NavigationSplitView {
            PreferenceSidebar(sections: SettingsSection.allCases, selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            detail
        }
        .toolbar(removing: .sidebarToggle)
        .frame(width: 680, height: 480)
        .alert(updateAlertTitle, isPresented: $showUpdateAlert, presenting: manualCheckResult) { result in
            switch result {
            case .available:
                Button("Cập nhật") { updateChecker.openReleasePage() }
                Button("Để sau", role: .cancel) {}
            case .upToDate, .failed:
                Button("OK", role: .cancel) {}
            }
        } message: { result in
            Text(updateAlertMessage(for: result))
        }
    }

    private func checkForUpdatesManually() {
        updateChecker.checkNow { result in
            manualCheckResult = result
            showUpdateAlert = true
        }
    }

    private var updateAlertTitle: String {
        switch manualCheckResult {
        case .available: "Có bản cập nhật mới"
        case .upToDate: "Đã cập nhật"
        case .failed, nil: "Không thể kiểm tra"
        }
    }

    private func updateAlertMessage(for result: UpdateCheckResult) -> String {
        switch result {
        case let .available(info): "Phiên bản \(info.version) đã có sẵn. Bạn có muốn tải bản cập nhật này không?"
        case .upToDate: "Bạn đang dùng phiên bản mới nhất (\(currentVersion))."
        case .failed: "Đã có lỗi xảy ra khi kiểm tra bản cập nhật. Vui lòng thử lại sau."
        }
    }

    private var detail: some View {
        Group {
            switch selection {
            case .general: generalPane
            case .notifications: notificationsPane
            case .appearance: appearancePane
            case .behavior: behaviorPane
            case .about: aboutPane
            }
        }
        .id(selection)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: selection)
    }

    private var generalPane: some View {
        PreferenceSection(title: selection.title) {
            PreferenceGroup(caption: "Hệ thống") {
                PreferenceToggleRow(title: "Khởi động cùng macOS", isOn: $settings.launchAtLogin)
            }

            PreferenceGroup(caption: "Cập nhật") {
                PreferenceToggleRow(title: "Tự động kiểm tra bản mới", isOn: $settings.checkForUpdatesAutomatically)
                PreferenceDivider()
                PreferenceRow(title: "Phiên bản hiện tại") {
                    HStack(spacing: 10) {
                        Text(currentVersion)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        Button("Kiểm tra ngay") { checkForUpdatesManually() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(updateChecker.isChecking)
                    }
                }
            }
        }
    }

    private var notificationsPane: some View {
        PreferenceSection(title: selection.title) {
            PreferenceGroup(
                caption: "Bluetooth",
                footnote: "macOS sẽ hỏi quyền truy cập Bluetooth ngay khi bạn bật mục này lần đầu."
            ) {
                PreferenceToggleRow(
                    title: "Phát hiện tai nghe Bluetooth",
                    subtitle: "Hiện thông báo kèm mức pin khi tai nghe Bluetooth kết nối (AirPods, Beats, và các loại khác).",
                    isOn: $settings.bluetoothHeadphoneDetectionEnabled
                )
            }
        }
    }

    private var appearancePane: some View {
        PreferenceSection(title: selection.title) {
            PreferenceGroup(caption: "Mở rộng khi hover") {
                PreferenceSliderRow(
                    title: "Độ trễ mở rộng",
                    valueLabel: "\(String(format: "%.2f", settings.hoverExpandDelay))s",
                    value: $settings.hoverExpandDelay,
                    range: 0...1,
                    step: 0.05
                )
            }
        }
    }

    private var behaviorPane: some View {
        PreferenceSection(title: selection.title) {
            PreferenceGroup(
                caption: "Đang phát",
                footnote: "Chỉ hoạt động với Safari và các trình duyệt gốc Chromium (Chrome, Brave, Edge, Vivaldi, Opera). "
                    + "macOS sẽ hỏi quyền điều khiển trình duyệt khi bạn bật mục này và bấm vào bài đang phát lần đầu."
            ) {
                PreferenceSliderRow(
                    title: "Tự ẩn sau khi dừng phát",
                    valueLabel: "\(Int(settings.pauseHideDelay))s",
                    value: $settings.pauseHideDelay,
                    range: 5...60,
                    step: 5
                )
                PreferenceDivider()
                PreferenceToggleRow(title: "Mở đúng tab trình duyệt khi bấm vào", isOn: $settings.browserTabJumpEnabled)
            }
        }
    }

    private var aboutPane: some View {
        PreferenceSection(title: selection.title) {
            PreferenceGroup(caption: "Niche") {
                PreferenceRow(title: "Phiên bản") {
                    Text(currentVersion)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                PreferenceDivider()
                PreferenceRow(title: "GitHub") {
                    Link("SangNef/niche", destination: URL(string: "https://github.com/SangNef/niche")!)
                        .font(.system(size: 13))
                }
            }
        }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
