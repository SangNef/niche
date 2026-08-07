import SwiftUI

/// The base row every other preference row is built from: a leading optional
/// icon, a title/subtitle stack, and a trailing accessory — laid out at the
/// ~42pt height native to macOS Settings rows, with a subtle hover highlight.
struct PreferenceRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    let accessory: Accessory

    @State private var isHovering = false

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 3) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            accessory
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlColor).opacity(isHovering ? 0.5 : 0))
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

extension PreferenceRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accessory = EmptyView()
    }
}
