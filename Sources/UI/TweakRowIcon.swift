import SwiftUI

struct TweakRowIcon: View {
    let systemImage: String
    let color: Color

    init(_ systemImage: String, color: Color = .blue) {
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: color.opacity(0.3), radius: 1, x: 0, y: 0.5)
            .accessibilityHidden(true)
    }
}

struct IconToggle: View {
    let title: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                TweakRowIcon(systemImage, color: color)
                Text(title)
            }
        }
        .disabled(disabled)
    }
}

struct IconPickerLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            TweakRowIcon(systemImage, color: color)
            Text(title)
        }
    }
}