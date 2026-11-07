import SwiftUI

struct TweakRowIcon: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 26, alignment: .center)
            .accessibilityHidden(true)
    }
}

struct IconToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                TweakRowIcon(systemImage: systemImage)
                Text(title)
            }
        }
        .disabled(disabled)
    }
}

struct IconPickerLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            TweakRowIcon(systemImage: systemImage)
            Text(title)
        }
    }
}