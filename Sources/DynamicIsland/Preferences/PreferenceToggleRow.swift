import SwiftUI

/// A `PreferenceRow` with a trailing switch — the workhorse row for boolean
/// settings throughout the Preferences window.
struct PreferenceToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        PreferenceRow(title: title, subtitle: subtitle, icon: icon) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
