import SwiftUI

/// A two-line row pairing a title/value header with a full-width slider —
/// used for continuous settings like delays and thresholds.
struct PreferenceSliderRow: View {
    let title: String
    var valueLabel: String? = nil
    var icon: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 18)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer()
                if let valueLabel {
                    Text(valueLabel)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
