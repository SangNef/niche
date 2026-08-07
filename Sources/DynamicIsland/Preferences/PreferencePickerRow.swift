import SwiftUI

/// A `PreferenceRow` with a trailing menu picker — used for settings backed
/// by a small closed set of options.
struct PreferencePickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @Binding var selection: SelectionValue
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        PreferenceRow(title: title, subtitle: subtitle, icon: icon) {
            Picker("", selection: $selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 160)
        }
    }
}
