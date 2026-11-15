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
        
        // Init Airlift logger
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
                VersionBlockedView() // LỖI CŨ LÀ DO THIẾU CÁI STRUCT NÀY
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
            "24A5390f", // 27.0 beta 4
            "24A5408d", // 27.0 beta 5
            "24A5418b", // 27.0 beta 6
            "24A5424a", // 27.0 beta 7
            "24A5430a", // 27.0 beta 8
            "24A435", // 27.0 RC
            "24A437", // 27.0
            "24A446", // 27.0.1 
            "24B5084k", // 27.2 beta 1
            "24B5089g", // 27.2 beta 2
            "24B5099f", // 27.2 beta 3
            "24B5110a", // 27.2 beta 4
            "24B115", // 27.2 RC
            "24B119", // 27.2
            "24B156", // 27.2.1
            "24C5037i", // 27.3 beta 1
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

// MARK: - MÀN HÌNH CHẶN (ĐÃ ĐƯỢC THÊM LẠI ĐẦY ĐỦ)
struct VersionBlockedView: View {
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false
    @AppStorage("hasChosenMode") private var hasChosenMode: Bool = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                
                Text("iOS Version Not Supported")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                Text("This app only supports iOS versions 27.0 To 27.3 Beta 1")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Your current iOS version:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text(UIDevice.current.systemVersion)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("To use this app:")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill").foregroundColor(.gray)
                        Text("Upgrade to iOS 27.2 or 27.3")
                            .foregroundColor(.gray).font(.subheadline)
                    }
                    
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle.fill").foregroundColor(.gray)
                        Text("Contact the developer for support")
                            .foregroundColor(.gray).font(.subheadline)
                    }
                    
                    Divider().background(Color.gray)
                    
                    Button(action: {
                        withAnimation {
                            isAirLiftMode = true
                            hasChosenMode = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "airplane.circle.fill")
                            Text("Continue with Airlift")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .padding(.top, 10)
                }
                .padding(20)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
}