import SwiftUI
import UIKit
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
                .tabItem { Label(L("nav_about"), systemImage: "info.circle.fill") }.tag(NavigationTab.about)

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
    @State private var statusLogs: [String] = [L("msg_apply_status_ready")]

    private var isApplying: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []

        if toolStore.disableCallRecordingSoundEnabled { list.append((L("tool_disable_sound"), "speaker.slash")) }
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        if walletStore.appleWalletEnabled { list.append((L("tool_apple_wallet"), "wallet.pass")) }
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if toolStore.configTweaksEnabled { list.append((L("tool_config_tweaks"), "textformat")) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("section_tweaks")).font(.headline).textCase(nil)) {
                    if enabledTweaks.isEmpty {
                        Text(L("apply_no_tweaks")).foregroundStyle(.secondary)
                    } else {
                        ForEach(enabledTweaks, id: \.0) { tweak in
                            Label { Text(tweak.0) } icon: { Image(systemName: tweak.1).foregroundStyle(.tint) }
                        }
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section {
                    Toggle(isOn: $toolStore.soundRespringEnabled) {
                        Text(L("respring_after_apply"))
                    }
                    Text(L("using_neospring")).font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))

                Section(header: Text(L("section_status")).font(.headline).textCase(nil)) {
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
                        title: isApplying ? L("applying") : L("apply_enabled_tweaks"),
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
        statusLogs = [L("apply_starting")]

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
                    statusLogs.append("❌ \(L("alert_error")): \(msg)")
                    showErrorAlert = true
                } else if toolRunner.state == .success {
                    statusLogs.append("✅ \(L("apply_done"))")
                }
            }

            if toolStore.soundRespringEnabled && toolRunner.state == .success {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                try? RespringHelper.respring()
            }
        }
    }
}

// MARK: - ABOUT VIEW (inline — KHÔNG tạo file mới, KHÔNG đụng Xcode project)
private struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    private func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return "\(UIDevice.current.model) (\(identifier))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text("EnsWilde").font(.title2.bold())
                    Text("v\(appVersion) (\(buildNumber))").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Label(L("app_ios"), systemImage: "iphone")
                    Spacer()
                    Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Label(L("app_device"), systemImage: "apps.iphone")
                    Spacer()
                    Text(deviceModelName()).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("settings_app_info"))
            }

            Section {
                Text(L("app_info_footer")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("nav_about"))
        .navigationBarTitleDisplayMode(.inline)
    }
}