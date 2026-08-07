import SwiftUI

/// A rounded card of related rows — the native "grouped list" look of
/// macOS System Settings, with an optional uppercase caption above it and a
/// footnote below.
struct PreferenceGroup<Content: View>: View {
    var caption: String? = nil
    var footnote: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption {
                Text(caption.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
