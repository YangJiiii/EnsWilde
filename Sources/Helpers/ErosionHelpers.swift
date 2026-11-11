import Foundation
import UIKit
import SwiftUI
import Combine

// MARK: - FileManager
let fm = FileManager.default

// MARK: - FSURL paths
enum FSPaths {
    static let appContainers = "/var/mobile/Containers/Data/Application"
    static let appBundles = "/var/containers/Bundle/Application"
}

enum FSURL {
    static let appContainers = URL(fileURLWithPath: FSPaths.appContainers)
    static var sysGroup = URL(fileURLWithPath: "/var/containers/Shared/SystemGroup")
    static var configProfiles = FSURL.sysGroup.appendingPathComponent("systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles")
    static var internalDaemons = URL(fileURLWithPath: "/var/mobile/Containers/Data/InternalDaemon")
    static var appPlugins = URL(fileURLWithPath: "/var/mobile/Containers/Data/PluginKitPlugin")
    static var appGroup = URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup")
    static var systemData = URL(fileURLWithPath: "/var/containers/Data/System")
}

// MARK: - AppMsg
enum AppMsg {
    static let opFailed = "Restart app và thử lại. Nếu vẫn lỗi → thiết bị hoặc tweak không được hỗ trợ."
    static let applied = "Respring để thay đổi có hiệu lực."
    static let unsupported = "Exploit đã bị patch trên phiên bản này."
}

// MARK: - AppURL
enum AppURL {
    static let pb = URL.documentsDirectory.appendingPathComponent("PosterBoard")
    static let pbFolders = AppURL.pb.appendingPathComponent("Wallpapers")
    static let ps = URL.documentsDirectory.appendingPathComponent("Passcode Themes")
}

// MARK: - Haptic
@MainActor
public class Haptic: ObservableObject {
    public static let shared = Haptic()

    public func play(_ feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1.0) {
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: feedbackStyle).impactOccurred(intensity: intensity)
        }
    }

    public func notify(_ feedbackType: UINotificationFeedbackGenerator.FeedbackType) {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(feedbackType)
        }
    }
}

// MARK: - FileManager extension
extension FileManager {
    func createDirIfNeeded(at url: URL) throws {
        if !self.fileExists(atPath: url.path) {
            try? self.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

// MARK: - String as Error
extension String: @retroactive Error {}

// MARK: - ButtonRole
extension ButtonRole {
    static var adaptiveConfirm: ButtonRole? {
        if #available(iOS 19.0, *) {
            return .confirm
        }
        return nil
    }
}

// MARK: - HeaderLabel
struct HeaderLabel: View {
    let text: String
    let symbol: String

    init(_ text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.bold())
    }
}

// MARK: - PlainToggle
struct PlainToggle: View {
    let label: String
    let infoType: InfoType
    let infoTitle: String
    let infoMessage: String
    @Binding var isOn: Bool

    enum InfoType {
        case warning, info
    }

    init(_ label: String,
         infoType: InfoType = .info,
         infoTitle: String = "",
         infoMessage: String = "",
         isOn: Binding<Bool>) {
        self.label = label
        self.infoType = infoType
        self.infoTitle = infoTitle
        self.infoMessage = infoMessage
        self._isOn = isOn
    }

    @State private var showInfo = false

    var body: some View {
        HStack {
            Toggle(label, isOn: $isOn)

            if !infoMessage.isEmpty {
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: infoType == .warning ? "exclamationmark.triangle" : "info.circle")
                        .foregroundStyle(infoType == .warning ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .alert(infoTitle, isPresented: $showInfo) {
            Button("OK") {}
        } message: {
            Text(infoMessage)
        }
    }
}