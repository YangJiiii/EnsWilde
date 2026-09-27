import FlyingFox
import SQLite3
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

@main
struct MyApp: App {
    // MARK: - Anti-Tamper Header
    // This constant serves as a visible warning in the binary to deter reverse engineering.
    // The dummy reference in init() prevents compiler optimization from stripping it.
    private static let antiTamperMessage: String = "Fuck you. Get out..."
    
    private static var httpServer: HTTPServer?

    init() {
        // Ensure antiTamperMessage is referenced so compiler doesn't optimize it away
        if Self.antiTamperMessage.isEmpty { return }
        
        // Set global tint color from user preference (default #ef9f76)
        let hexString = UserDefaults.standard.string(forKey: "EnsWilde.userTintColor") ?? "#ef9f76"
        let tintColor = UIColor(Color(hex: hexString))
        UIView.appearance(whenContainedInInstancesOf: [UIWindow.self]).tintColor = tintColor
        UITabBar.appearance().tintColor = tintColor
        UINavigationBar.appearance().tintColor = tintColor
        
        // Check iOS version compatibility on launch
        let versionSupported = Utils.isIOSVersionSupported()
        let versionString = Utils.getIOSVersionString()
        
        if !versionSupported {
            print("⚠️ [VERSION CHECK] Unsupported iOS version detected: \(versionString)")
            print("⚠️ [VERSION CHECK] App requires iOS 18.0 or later")
        } else {
            print("✅ [VERSION CHECK] iOS version \(versionString) is supported")
        }
        
        Task.detached { @MainActor in
            do {
                Utils.port = try Utils.reservePort()

                let server = HTTPServer(port: Utils.port)
                Self.httpServer = server

                await server.appendRoute("GET /*", to: DirectoryHTTPHandler(root: URL.documentsDirectory))
                try await server.run()
            } catch {
                Utils.port = 0
                print("[HTTP] server failed: \(error)")
            }
        }

        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)

        // Request notification permission at launch
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            if Utils.isIOSVersionSupported() {
                MainViewWithNavigation()
            } else {
                UnsupportedVersionView()
            }
        }
    }
}

// MARK: - Unsupported Version View
struct UnsupportedVersionView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
                
                VStack(spacing: 12) {
                    Text("iOS Version Not Supported")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    Text("This app requires iOS 18.0 or later")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    VStack(spacing: 6) {
                        Text("Your current iOS version:")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Text(Utils.getIOSVersionString())
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                    }
                    .padding(.top, 8)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("To use this app:")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if Utils.os.majorVersion < 18 {
                        Label("Upgrade your iOS to version 18.0 or later", systemImage: "arrow.up.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Label("Contact the developer for support", systemImage: "questionmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal, 32)
                .padding(.top, 12)
            }
            .padding()
        }
    }
}
