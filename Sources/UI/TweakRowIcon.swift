import SwiftUI

/// Icon đơn sắc kiểu iOS Settings (giống hình mẫu: xám, không background).
struct TweakRowIcon: View {
    let systemImage: String

    init(_ systemImage: String) {
        self.systemImage = systemImage
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 26, alignment: .center)
            .accessibilityHidden(true)
    }
}

/// Wrapper Toggle đơn giản (dùng khi cần icon trước text).
struct IconToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                TweakRowIcon(systemImage)
                Text(title)
            }
        }
        .disabled(disabled)
    }
}

/// Wrapper Picker (dùng khi cần icon trước text).
struct IconPickerLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            TweakRowIcon(systemImage)
            Text(title)
        }
    }
}