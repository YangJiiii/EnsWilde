import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
    
    init(hex string: String) {
        let hex = string.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0xef / 255.0; g = 0x9f / 255.0; b = 0x76 / 255.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
    
    static func disabled() -> Color { return Color.secondary }
}

struct AppTheme {
    static let bg = Color(.systemGroupedBackground)
    static let row = Color(.secondarySystemGroupedBackground)
    static let textSecondary = Color.secondary
    
    static var accent: Color {
        let hex = UserDefaults.standard.string(forKey: "EnsWilde.userTintColor") ?? "#ef9f76"
        return Color(hex: hex)
    }
    
    static func font(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        return .system(style, weight: weight)
    }
}

struct WalletStyleButton: View {
    let title: String
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(.white) }
                Text(title).font(.headline.bold())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AppTheme.accent)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.55 : 1.0)
        .disabled(disabled)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct SecondaryActionButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.quaternarySystemFill))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.35 : 1.0)
        .disabled(disabled)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct AppTitleHeader: View { var body: some View { EmptyView() } }
struct AppSectionHeader: View { let title: String; var body: some View { EmptyView() } }

struct CardRow: View {
    let title: String
    let subtitle: String?
    let ok: Bool?
    let showChevron: Bool
    let trailing: AnyView?

    var body: some View {
        HStack(spacing: 12) {
            if let ok { Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill").foregroundStyle(ok ? .green : .red) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(ok == true ? .green : (ok == false ? .red : .secondary)).lineLimit(2)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}