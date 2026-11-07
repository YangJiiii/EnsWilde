import SwiftUI

// MARK: - TweakRowIcon (hỗ trợ cả 2 kiểu gọi: có/không label + có/không color)
struct TweakRowIcon: View {
    let systemImage: String
    var color: Color?

    // Kiểu không label: TweakRowIcon("foo") và TweakRowIcon("foo", color: .red)
    init(_ systemImage: String, color: Color? = nil) {
        self.systemImage = systemImage
        self.color = color
    }

    // Kiểu có label: TweakRowIcon(systemImage: "foo") và TweakRowIcon(systemImage: "foo", color: .red)
    init(systemImage: String, color: Color? = nil) {
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        // Nếu có color thì dùng, không có thì giữ nguyên `.secondary` như bản gốc
        if let color {
            baseImage.foregroundStyle(color)
        } else {
            baseImage.foregroundStyle(.secondary)
        }
    }

    private var baseImage: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .medium))
            .frame(width: 26, alignment: .center)
            .accessibilityHidden(true)
    }
}

// MARK: - IconToggle (thêm color với default = nil, giữ nguyên toàn bộ call site cũ)
struct IconToggle: View {
    let title: String
    let systemImage: String
    var color: Color?
    @Binding var isOn: Bool
    var disabled: Bool

    init(title: String,
         systemImage: String,
         color: Color? = nil,
         isOn: Binding<Bool>,
         disabled: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self._isOn = isOn
        self.disabled = disabled
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                TweakRowIcon(systemImage: systemImage, color: color)
                Text(title)
            }
        }
        .disabled(disabled)
    }
}

// MARK: - IconPickerLabel (thêm color với default = nil)
struct IconPickerLabel: View {
    let title: String
    let systemImage: String
    var color: Color?

    init(title: String, systemImage: String, color: Color? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            TweakRowIcon(systemImage: systemImage, color: color)
            Text(title)
        }
    }
}