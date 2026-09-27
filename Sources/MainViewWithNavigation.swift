import SwiftUI
import UserNotifications

enum NavigationTab {
    case home, settings, about, apply
}

struct MainViewWithNavigation: View {
    @State private var selectedTab: NavigationTab = .home
    @StateObject private var themeStore = PasscodeThemeStore()
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var featureFlagsStore = FeatureFlagsStore()
    @State private var showApplySheet = false
    @State private var showStatusSheet = false
    @State private var isInNestedView = false
    @State private var isSystemReady = true
    @State private var heartbeatRunning = false
    @State private var ddiMounted = false
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var tintRefreshID = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(
                themeStore: themeStore,
                toolStore: toolStore,
                toolRunner: toolRunner,
                walletStore: walletStore,
                featureFlagsStore: featureFlagsStore,
                showApplySheetBinding: $showApplySheet,
                showStatusSheetBinding: $showStatusSheet,
                hideBottomApplyButton: true,
                isInNestedViewBinding: $isInNestedView,
                isSystemReadyBinding: $isSystemReady,
                heartbeatRunningBinding: $heartbeatRunning,
                ddiMountedBinding: $ddiMounted
            )
            .tabItem {
                Label(L("nav_home"), systemImage: "house.fill")
            }
            .tag(NavigationTab.home)

            NavigationStack {
                ThemeStoreView(themeStore: themeStore)
            }
            .tabItem {
                Label(L("nav_theme_store"), systemImage: "square.grid.2x2.fill")
            }
            .tag(NavigationTab.home)

            NavigationStack {
                SettingsView(heartbeatRunning: false, ddiMounted: false)
            }
            .tabItem {
                Label(L("nav_settings"), systemImage: "gearshape.fill")
            }
            .tag(NavigationTab.settings)

            NavigationStack {
                AboutView()
            }
            .tabItem {
                Label(L("nav_about"), systemImage: "info.circle.fill")
            }
            .tag(NavigationTab.about)

            ApplyTabView(
                toolStore: toolStore,
                toolRunner: toolRunner,
                walletStore: walletStore,
                themeStore: themeStore,
                featureFlagsStore: featureFlagsStore,
                isSystemReady: true
            )
            .tabItem {
                Label(L("nav_apply"), systemImage: "checkmark.circle.fill")
            }
            .tag(NavigationTab.apply)
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
            for window in windowScene.windows {
                window.tintColor = uiColor
            }
        }
        tintRefreshID = UUID()
    }
}

struct ApplyTabView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore
    var isSystemReady: Bool

    @State private var showErrorAlert = false
    @State private var lastError: String?

    private var isRunning: Bool {
        if case .running = toolRunner.state { return true }
        return false
    }

    private var enabledTweaks: [(String, String)] {
        var list: [(String, String)] = []
        if toolStore.replaceMobileGestaltEnabled { list.append((L("tool_mobile_gestalt"), "cpu")) }
        if themeStore.passcodeThemeEnabled { list.append((L("tool_passcode_theme"), "lock.rectangle")) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                enabledTweaksSection
                optionsSection
                statusSection
                applyButtonSection
            }
            .headerProminence(.increased)
            .navigationTitle(L("nav_apply"))
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(lastError ?? L("msg_error_unknown"))
        }
    }

    @ViewBuilder
    private var enabledTweaksSection: some View {
        Section(header: Text(L("section_tweaks"))) {
            if enabledTweaks.isEmpty {
                Label {
                    Text(L("apply_no_tweaks_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(enabledTweaks, id: \.0) { tweak in
                    Label {
                        Text(tweak.0)
                    } icon: {
                        Image(systemName: tweak.1)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section(header: Text(L("section_options"))) {
            Toggle(isOn: $toolStore.soundRespringEnabled) {
                Label(L("respring_after_apply"), systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if isRunning || statusText != "" {
            Section {
                HStack(spacing: 12) {
                    if isRunning { ProgressView() }
                    Text(latestLogOrStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var latestLogOrStatus: String {
        if isRunning, let lastLog = toolRunner.logs.last?.text { return lastLog }
        return statusText
    }

    @ViewBuilder
    private var applyButtonSection: some View {
        Section {
            WalletStyleButton(
                title: isRunning ? L("applying") : L("apply_enabled_tweaks"),
                isLoading: isRunning,
                disabled: isRunning || enabledTweaks.isEmpty,
                action: performApply
            )
        }
    }

    private var statusText: String {
        switch toolRunner.state {
        case .idle:
            if enabledTweaks.isEmpty { return L("apply_enable_first") }
            return L("apply_ready").replacingOccurrences(of: "{count}", with: "\(enabledTweaks.count)")
        case .running(let toolName):
            return L("apply_running").replacingOccurrences(of: "{toolName}", with: toolName)
        case .success:
            return L("apply_done")
        case .failed(let message):
            return L("apply_failed").replacingOccurrences(of: "{message}", with: message)
        }
    }

    private func performApply() {
        Task {
            await toolRunner.applyAll(
                store: toolStore,
                themeStore: themeStore
            )

            if case .success = toolRunner.state {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if toolStore.soundRespringEnabled {
                    try? RespringHelper.respring()
                } else {
                    if let bundleID = Bundle.main.bundleIdentifier {
                        LSApplicationWorkspaceDefaultWorkspace().openApplication(withBundleID: bundleID)
                    }
                }
            }

            if case .failed(let message) = toolRunner.state {
                lastError = message
                showErrorAlert = true
            }
        }
    }
}