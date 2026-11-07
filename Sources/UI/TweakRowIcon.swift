import SwiftUI

/// Icon kiểu System Settings.app — vuông bo góc, gradient nhẹ, symbol trắng.
/// Kích thước 29×29, corner 7 — giống hệt Settings iOS.
struct TweakRowIcon: View {
    let systemImage: String
    let color: Color

    init(_ systemImage: String, color: Color) {
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
                            colors: [color.opacity(0.98), color.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                            .blendMode(.overlay)
                    )
                    .shadow(color: color.opacity(0.25), radius: 1, x: 0, y: 0.5)
            )
            .accessibilityHidden(true)
    }
}

/// Wrapper Toggle có icon bên trái — style System Settings.
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

/// Wrapper Picker có icon bên trái.
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
