import SwiftUI

/// The scrollable detail pane for one sidebar destination: a large title
/// (matching the System Settings pane header) followed by a vertical stack
/// of `PreferenceGroup`s, centered with a comfortable reading width.
struct PreferenceSection<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                VStack(alignment: .leading, spacing: 20) {
                    content
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
