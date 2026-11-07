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
            NavigationStack { ContentView(themeStore: themeStore, toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, featureFlagsStore: featureFlagsStore) }
                .tabItem { Label(L("nav_home"), systemImage: "house.fill") }.tag(NavigationTab.home)
            
            NavigationStack { ThemeStoreView(themeStore: themeStore) }
                .tabItem { Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill") }.tag(NavigationTab.themeStore)
            
            NavigationStack { SettingsView(toolStore: toolStore) }
                .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }.tag(NavigationTab.settings)
            
            NavigationStack { AboutView() }
                .tabItem { Label("About", systemImage: "info.circle.fill") }.tag(NavigationTab.about)
            
            if showApplyTab {
                ApplyTabView(toolStore: toolStore, toolRunner: toolRunner, walletStore: walletStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)
                .tabItem { Label(L("nav_apply"), systemImage: "checkmark.circle.fill") }.tag(NavigationTab.apply)
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
    @State private var statusLogs: [String] = ["Ready to apply."]
    
    private var isApplying: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    // DANH SÁCH CÁC TWEAK ĐANG BẬT
    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        
        // ĐÃ SỬA ICON THÀNH speaker.slash CHO KHỚP VỚI TRANG CHỦ
        if toolStore.disableCallRecordingSoundEnabled { list.append(("Disable Call Recording Sound", "speaker.slash")) }
        
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if toolStore.configTweaksEnabled { list.append((L("tool_config_tweaks"), "textformat")) }
        return list
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
                    Text("Using Neospring to Respring device").font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section(header: Text("Status").font(.headline).textCase(nil)) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(statusLogs.indices, id: \.self) { index in
                                    Text(statusLogs[index])
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .foregroundStyle(statusLogs[index].hasPrefix("✅") ? .green : (statusLogs[index].hasPrefix("❌") ? .red : .secondary))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Spacer().id("bottom")
                            }
                        }
                        .frame(height: 150)
                        .onChange(of: statusLogs.count) { _ in
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
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
            }
            .navigationTitle(L("nav_apply"))
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
    }

    private func performApply() {
        statusLogs = ["Starting Apply sequence..."]
        
        Task.detached(priority: .userInitiated) {
            await toolRunner.applyAll(
                isSystemReady: true,
                store: toolStore,
                walletStore: walletStore,
                themeStore: themeStore,
                featureFlagsStore: featureFlagsStore,
                onLogUpdate: { message in
                    DispatchQueue.main.async {
                        self.statusLogs.append(message)
                    }
                }
            )
            
            await MainActor.run {
                if case .failed(let msg) = toolRunner.state {
                    lastError = msg
                    statusLogs.append("❌ Lỗi: \(msg)")
                    showErrorAlert = true
                } else if toolRunner.state == .success {
                    statusLogs.append("✅ Applied successfully.")
                }
            }
            
            if toolStore.soundRespringEnabled && toolRunner.state == .success {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                try? RespringHelper.respring()
            }
        }
    }
}