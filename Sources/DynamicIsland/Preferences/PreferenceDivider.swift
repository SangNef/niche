import SwiftUI

/// Hairline separator used between rows inside a `PreferenceGroup`, inset to
/// align with row content rather than running edge-to-edge.
struct PreferenceDivider: View {
    var leadingInset: CGFloat = 14

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}
