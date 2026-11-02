import SwiftUI
import UserNotifications
import AirliftFFI

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ContentView(themeStore: themeStore, toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, featureFlagsStore: featureFlagsStore)
            }
            .tabItem { Label(L("nav_home"), systemImage: "house.fill") }
            .tag(NavigationTab.home)
            
            NavigationStack { ThemeStoreView(themeStore: themeStore) }
            .tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }
            .tag(NavigationTab.themeStore)
            
            NavigationStack { SettingsView(toolStore: toolStore) }
            .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }
            .tag(NavigationTab.settings)
            
            NavigationStack { AboutView() }
            .tabItem { Label("About", systemImage: "info.circle.fill") }
            .tag(NavigationTab.about)
            
            if showApplyTab {
                ApplyTabView(toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)
                .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }
                .tag(NavigationTab.apply)
            }
        }
        .tint(Color(hex: userTintColorHex))
        .id(tintRefreshID)
        .onChange(of: userTintColorHex) { _ in applyTintColor() }
        .onAppear { applyTintColor() }
    }
    
    private func applyTintColor() {
        let uiColor = UIColor(Color(hex: userTintColorHex))
        UITabBar.appearance().tintColor = uiColor
        UINavigationBar.appearance().tintColor = uiColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.tintColor = uiColor }
        }
        tintRefreshID = UUID()
    }
}

// MARK: - APPLY TAB VIEW
struct ApplyTabView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore

    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"

    @State private var showErrorAlert = false
    @State private var lastError: String?
    @State private var fullLogText: String = ""
    @State private var showCopiedAlert = false
    
    private var isApplying: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if toolStore.configTweaksEnabled { list.append((L("tool_config_tweaks"), "textformat")) }
        return list
    }
    
    private var currentStatus: String {
        if isApplying { return "Applying..." }
        return "Ready to apply."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tweaks").font(.headline).textCase(nil)) {
                    if enabledTweaks.isEmpty {
                        Text("No tweaks enabled.").foregroundStyle(.secondary)
                    } else {
                        ForEach(enabledTweaks, id: \.0) { tweak in
                            Label { Text(tweak.0) } icon: { Image(systemName: tweak.1).foregroundStyle(.tint) }
                        }
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    Toggle(isOn: $toolStore.soundRespringEnabled) {
                        Text("Respring after apply")
                    }
                    Text("Using Neospring to Respring device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section(header: Text("Status").font(.headline).textCase(nil)) {
                    HStack(spacing: 12) {
                        if isApplying {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.orange))
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                        }
                        
                        Text(currentStatus)
                            .font(.subheadline)
                            .foregroundStyle(isApplying ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    WalletStyleButton(
                        title: isApplying ? "Applying..." : L("apply_enabled_tweaks"),
                        isLoading: isApplying,
                        disabled: isApplying,
                        action: performApply
                    )
                }

                // LOG VIEWER MỚI
                Section(header: HStack {
                    Text("Execution Log").font(.headline).textCase(nil)
                    Spacer()
                    Button(action: { fullLogText = "" }) {
                        Text("Clear").font(.caption).foregroundStyle(.red)
                    }
                }) {
                    LogViewer(logText: $fullLogText)
                        .frame(minHeight: 200)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle(L("nav_apply"))
            .onReceive(NotificationCenter.default.publisher(for: .airliftLog)) { notif in
                if let line = notif.userInfo?["line"] as? String {
                    fullLogText += line + "\n"
                }
            }
            .onChange(of: isApplying) { applying in
                if applying { fullLogText = "" } // Xoá log cũ khi bắt đầu chạy
            }
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
    }

    private func performApply() {
        Task {
            await toolRunner.applyAll(
                isSystemReady: true,
                store: toolStore,
                walletStore: walletStore,
                themeStore: themeStore,
                featureFlagsStore: featureFlagsStore
            )
            
            await MainActor.run {
                if case .failed(let msg) = toolRunner.state {
                    lastError = msg
                    showErrorAlert = true
                }
            }
            
            if toolStore.soundRespringEnabled && toolRunner.state == .success {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                try? RespringHelper.respring()
            }
        }
    }
}

// MARK: - LOG VIEWER COMPONENT
struct LogViewer: View {
    @Binding var logText: String
    @State private var showCopiedAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    UIPasteboard.general.string = logText
                    showCopiedAlert = true
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.bold())
                }
                .padding(.trailing, 8)
                
                ShareLink(item: logText, preview: SharePreview("Log", image: Image(systemName: "doc.text"))) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            
            Divider()
            
            ScrollView {
                Text(logText.isEmpty ? "Chưa có log..." : logText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 150, maxHeight: 300)
            .background(Color(UIColor.systemBackground))
        }
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .alert("Đã copy!", isPresented: $showCopiedAlert) { Button("OK", role: .cancel) {} }
    }
}