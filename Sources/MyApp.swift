import SwiftUI
import AirliftFFI

extension Notification.Name {
    static let airliftLog = Notification.Name("airlift.log")
}

@main
struct MyApp: App {
    @AppStorage("hasChosenMode") private var hasChosenMode: Bool = false
    
    init() {
        UserDefaults.standard.set(false, forKey: "ShowApplyTab")
        
        al_log_init({ _, msg in
            guard let msg = msg else { return }
            let line = String(cString: msg)
            NSLog("[Airlift] %@", line)
            NotificationCenter.default.post(
                name: .airliftLog,
                object: nil,
                userInfo: ["line": line]
            )
        }, nil)
    }
    
    var body: some Scene {
        WindowGroup {
            if !hasChosenMode && isVersionBlocked() {
                VersionBlockedView()
            } else {
                MainViewWithNavigation()
            }
        }
    }
    
    private func isVersionBlocked() -> Bool {
        let version = UIDevice.current.systemVersion
        guard version.hasPrefix("27.") || version == "27" else { return false }
        
        let build = getCleanBuildNumber()
        let supportedBuilds = [
            "24A5355q", // 27.0 beta 1
            "24A5370h", // 27.0 beta 2
            "24A5380h", // 27.0 beta 3
            "24A5390f"  // 27.0 beta 4
        ]
        
        if supportedBuilds.contains(build) {
            return false
        }
        return true
    }
    
    private func getCleanBuildNumber() -> String {
        var size: size_t = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var build = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &build, &size, nil, 0)
        return String(cString: build).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}