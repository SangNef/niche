import SwiftUI

/// Native-style Settings sidebar: a column of icon+label rows with a pill
/// selection highlight that glides between rows via `matchedGeometryEffect`,
/// rather than the flat highlight `List(selection:)` gives you for free.
struct PreferenceSidebar: View {
    let sections: [PreferencesView.SettingsSection]
    @Binding var selection: PreferencesView.SettingsSection

    @Namespace private var selectionNamespace

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(sections) { section in
                    PreferenceSidebarRow(
                        section: section,
                        isSelected: section == selection,
                        namespace: selectionNamespace
                    ) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
        .background(.ultraThinMaterial)
    }
}

private struct PreferenceSidebarRow: View {
    let section: PreferencesView.SettingsSection
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "sidebarSelection", in: namespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlColor).opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
