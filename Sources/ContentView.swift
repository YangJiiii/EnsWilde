import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Network

// MARK: - Main ContentView

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    // Localization
    @ObservedObject private var localizationManager = LocalizationManager.shared

    // Pairing
    @AppStorage("PairingFile") private var pairingFile: String?

    // Services state
    @State private var heartbeatRunning = false
    @State private var ddiMounted = false

    // UI state
    @State private var showPairingFileImporter = false
    @State private var showErrorAlert = false
    @State private var lastError: String?
    @State private var showStatusSheet = false
    @State private var _showApplySheet = false
    @State private var path = NavigationPath()
    @State private var showUUIDAlert = false
    
    // Binding for external control of apply sheet (default to internal state)
    var showApplySheetBinding: Binding<Bool>? = nil
    var showStatusSheetBinding: Binding<Bool>? = nil
    
    // Hide the bottom Apply button when using navigation bar
    var hideBottomApplyButton: Bool = false
    
    // Optional bindings to track navigation state
    var isInNestedViewBinding: Binding<Bool>?
    var isSystemReadyBinding: Binding<Bool>?
    
    // Internal state for when used standalone
    @State private var _isInNestedView = false
    @State private var _isSystemReadyState = false
    
    // Computed bindings
    private var isInNestedView: Binding<Bool> {
        isInNestedViewBinding ?? $_isInNestedView
    }
    
    private var isSystemReady: Binding<Bool> {
        isSystemReadyBinding ?? $_isSystemReadyState
    }
    
    // Computed property to handle both internal and external control
    private var showApplySheet: Binding<Bool> {
        showApplySheetBinding ?? $_showApplySheet
    }
    
    private var statusSheet: Binding<Bool> {
        showStatusSheetBinding ?? $showStatusSheet
    }
    
    // Computed system ready state
    private var _isSystemReady: Bool {
        pairingFile != nil && heartbeatRunning && ddiMounted
    }

    // Tools
    @StateObject private var toolStore = ToolStore()
    @StateObject private var toolRunner = ToolRunner()
    @StateObject private var walletStore = AppleWalletStore()
    @StateObject private var themeStore = PasscodeThemeStore()

    // Update check
    private let versionJSONURL = URL(string: "https://raw.githubusercontent.com/YangJiiii/EnsWilde/refs/heads/main/version.json")!
    @State private var showUpdateAlert = false
    @State private var updateURL: URL?
    @State private var updateMessage: String = ""
    @State private var lastCheckedBuild: Int = -1
    @AppStorage("IgnoredUpdateBuild") private var ignoredUpdateBuild: Int = 0
    @State private var pendingRemoteBuild: Int = 0
    
    // Network monitoring for VPN auto-refresh
    @State private var networkMonitor: NWPathMonitor?
    
    // Animation Config (Hiệu ứng trượt mượt mà)
    private let panelAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    
    // Custom initializer to accept optional bindings
    init(
        showApplySheetBinding: Binding<Bool>? = nil,
        showStatusSheetBinding: Binding<Bool>? = nil,
        hideBottomApplyButton: Bool = false,
        isInNestedViewBinding: Binding<Bool>? = nil,
        isSystemReadyBinding: Binding<Bool>? = nil
    ) {
        self.showApplySheetBinding = showApplySheetBinding
        self.showStatusSheetBinding = showStatusSheetBinding
        self.hideBottomApplyButton = hideBottomApplyButton
        self.isInNestedViewBinding = isInNestedViewBinding
        self.isSystemReadyBinding = isSystemReadyBinding
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // Background
                AppTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 8) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                AppTitleHeader()
                            }
                            Spacer()

                            // Settings -> PUSH (không sheet)
                            Button {
                                path.append("Settings")
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.white.opacity(0.8))
                            }
                            .padding(.trailing, 20)
                            .padding(.top, 10)
                        }

                        // --- Section: STATUS ---
                        AppSectionHeader(title: L("section_status"))

                        Button {
                            withAnimation(panelAnimation) { statusSheet.wrappedValue = true }
                        } label: {
                            CardRow(
                                title: L("system_status"),
                                subtitle: _isSystemReady ? L("system_status_ready") : L("system_status_not_ready"),
                                ok: _isSystemReady,
                                showChevron: true,
                                trailing: nil
                            )
                        }
                        .padding(.horizontal, 20)

                        // Error Indicators
                        if pairingFile == nil {
                            Button(action: { showPairingFileImporter = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("pairing_file_missing"))
                                            .foregroundStyle(.white)
                                            .font(.system(size: 17, weight: .medium, design: .rounded))
                                        Text(L("pairing_file_import_prompt"))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                    }
                                    Spacer()
                                }
                                .padding(18)
                                .background(AppTheme.row)
                                .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                        }

                        if !heartbeatRunning && pairingFile != nil {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("heartbeat_not_running"))
                                        .foregroundStyle(.white)
                                        .font(.system(size: 17, weight: .medium, design: .rounded))
                                    Text(L("heartbeat_enable_vpn"))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                }
                                Spacer()
                            }
                            .padding(18)
                            .background(AppTheme.row)
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                        }

                        if !ddiMounted && pairingFile != nil && heartbeatRunning {
                            HStack(spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("ddi_not_mounted"))
                                        .foregroundStyle(.white)
                                        .font(.system(size: 17, weight: .medium, design: .rounded))
                                    Text(L("ddi_auto_mount_attempt"))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                }
                                Spacer()
                            }
                            .padding(18)
                            .background(AppTheme.row)
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                        }

                        // --- Section: TWEAKS ---
                        AppSectionHeader(title: L("section_tweaks"))

                        VStack(spacing: 0) {
                            NavigationLink(value: "MobileGestalt") {
                                HStack(spacing: 12) {
                                    if let ok = (toolStore.replaceMobileGestaltEnabled ? true : nil) {
                                        Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(ok ? .green : Color.white.opacity(0.55))
                                    } else {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.20))
                                            .padding(.horizontal, 4)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("tool_mobile_gestalt"))
                                            .foregroundStyle(.white)
                                            .font(.system(size: 17, weight: .medium, design: .rounded))
                                        Text(L("tool_mobile_gestalt_desc"))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.white.opacity(0.55))
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(18)
                                .background(AppTheme.row)
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.1))

                            NavigationLink(value: "DisableSound") {
                                HStack(spacing: 12) {
                                    if let ok = (toolStore.disableSoundEnabled ? true : nil) {
                                        Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(ok ? .green : Color.white.opacity(0.55))
                                    } else {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.20))
                                            .padding(.horizontal, 4)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("tool_disable_sound"))
                                            .foregroundStyle(.white)
                                            .font(.system(size: 17, weight: .medium, design: .rounded))
                                        Text(L("tool_disable_sound_desc"))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.white.opacity(0.55))
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(18)
                                .background(AppTheme.row)
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.1))

                            NavigationLink(value: "AppleWallet") {
                                HStack(spacing: 12) {
                                    if let ok = (walletStore.appleWalletEnabled ? true : nil) {
                                        Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(ok ? .green : Color.white.opacity(0.55))
                                    } else {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.20))
                                            .padding(.horizontal, 4)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("tool_apple_wallet"))
                                            .foregroundStyle(.white)
                                            .font(.system(size: 17, weight: .medium, design: .rounded))
                                        Text(L("tool_apple_wallet_desc"))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.white.opacity(0.55))
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(18)
                                .background(AppTheme.row)
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.1))

                            NavigationLink(value: "PasscodeTheme") {
                                HStack(spacing: 12) {
                                    if let ok = (themeStore.passcodeThemeEnabled ? true : nil) {
                                        Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(ok ? .green : Color.white.opacity(0.55))
                                    } else {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.20))
                                            .padding(.horizontal, 4)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("tool_passcode_theme"))
                                            .foregroundStyle(.white)
                                            .font(.system(size: 17, weight: .medium, design: .rounded))
                                        Text(L("tool_passcode_theme_desc"))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.white.opacity(0.55))
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(18)
                                .background(AppTheme.row)
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.1))

                            NavigationLink(value: "ThemesUI") {
                                HStack(spacing: 12) {
                                    if let ok = (toolStore.themesUIEnabled ? true : nil) {
                                        Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(ok ? .green : Color.white.opacity(0.55))
                                    } else {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.20))
                                            .padding(.horizontal, 4)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("tool_themes_ui"))
                                            .foregroundStyle(.white)
                                            .font(.system(size: 17, weight: .medium, design: .rounded))
                                        Text(L("tool_themes_ui_desc"))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.white.opacity(0.55))
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(18)
                                .background(AppTheme.row)
                            }
                            .buttonStyle(.plain)

                            // zPatch Custom (only show if unlocked)
                            if toolStore.zPatchUnlocked {
                                Divider().background(Color.white.opacity(0.1))
                                
                                NavigationLink(value: "zPatchCustom") {
                                    HStack(spacing: 12) {
                                        if let ok = (toolStore.zPatchCustomEnabled ? true : nil) {
                                            Image(systemName: ok ? "checkmark.seal.fill" : "xmark.seal.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundStyle(ok ? .green : Color.white.opacity(0.55))
                                        } else {
                                            Image(systemName: "circle.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(Color.white.opacity(0.20))
                                                .padding(.horizontal, 4)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(L("tool_zpatch_custom"))
                                                .foregroundStyle(.white)
                                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                            Text(L("tool_zpatch_custom_desc"))
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(Color.white.opacity(0.55))
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .padding(18)
                                    .background(AppTheme.row)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(AppTheme.row)
                        .cornerRadius(16)
                        .padding(.horizontal, 20)

                        // Footer
                        VStack(spacing: 8) {
                            Text(appVersionFooter)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                            Text("Built With By YangJiii")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 20)

                        Spacer(minLength: 160)
                    }
                    .padding(.top, 6)
                }

                // --- APPLY BUTTON PANEL (Panel Style) ---
                if !hideBottomApplyButton {
                    VStack {
                        Spacer()
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 40, height: 5)
                                .padding(.vertical, 16)
                            
                            WalletStyleButton(title: L("apply_button"), isLoading: false, disabled: !_isSystemReady) {
                                withAnimation(panelAnimation) { showApplySheet.wrappedValue = true }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .background(AppTheme.bg.padding(.bottom, -100).ignoresSafeArea())
                        .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: -5)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .zIndex(5)
                }
                
                // --- CUSTOM SHEETS OVERLAY ---
                // Lưu ý: Đặt cuối ZStack để đè lên mọi thứ
                
                // 1. STATUS SHEET
                if statusSheet.wrappedValue {
                    // Lớp nền tối (Fade)
                    Color.black.opacity(0.3)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .zIndex(10) // Đảm bảo nằm trên nội dung chính
                        .transition(.opacity)
                        .onTapGesture { withAnimation(panelAnimation) { statusSheet.wrappedValue = false } }
                    
                    // Panel nội dung (Slide up)
                    VStack {
                        Spacer() // Đẩy sheet xuống đáy
                        StatusSheet(
                            pairingFileLoaded: .constant(pairingFile != nil),
                            heartbeatRunning: $heartbeatRunning,
                            ddiMounted: $ddiMounted,
                            onImportPairing: { showPairingFileImporter = true },
                            onResetPairing: { resetPairing() },
                            onMountDDI: {
                                // Trigger manual DDI mount
                                attemptAutoMountDDI()
                            },
                            onClose: { withAnimation(panelAnimation) { statusSheet.wrappedValue = false } }
                        )
                    }
                    .ignoresSafeArea(edges: .bottom) // Để trượt từ mép màn hình vật lý
                    .zIndex(11) // Nằm trên lớp nền
                    .transition(.move(edge: .bottom)) // Hiệu ứng trượt chuẩn
                }

                // 2. APPLY SHEET
                if showApplySheet.wrappedValue {
                    // Lớp nền tối (Fade)
                    Color.black.opacity(0.3)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .zIndex(20)
                        .transition(.opacity)
                        .onTapGesture { withAnimation(panelAnimation) { showApplySheet.wrappedValue = false } }
                    
                    // Panel nội dung (Slide up)
                    VStack {
                        Spacer()
                        ApplySheet(
                            logs: .constant(toolRunner.logs.map { $0.text }),
                            isRunning: .constant(isApplyRunning(toolRunner.state)),
                            progressText: .constant(applyStatusText(toolRunner.state)),
                            enableRespring: $toolStore.soundRespringEnabled,
                            bookassetdUUID: .constant(toolStore.bookassetdUUID ?? ""),
                            onApply: {
                                Task {
                                    if toolStore.bookassetdUUID == nil || toolStore.bookassetdUUID?.isEmpty == true {
                                        showUUIDAlert = true
                                        return
                                    }
                                    
                                    await toolRunner.applyAll(isSystemReady: _isSystemReady, store: toolStore, walletStore: walletStore, themeStore: themeStore)
                                    
                                    if case .success = toolRunner.state {
                                        try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds delay before respring
                                        
                                        if toolStore.soundRespringEnabled {
                                            try? respringNow()
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
                            },
                            onClearUUID: { toolStore.bookassetdUUID = nil },
                            onClose: { withAnimation(panelAnimation) { showApplySheet.wrappedValue = false } }
                        )
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .zIndex(21)
                    .transition(.move(edge: .bottom))
                }

            } // ZStack End
            .navigationDestination(for: String.self) { route in
                if route == "DisableSound" {
                    DisableSoundView()
                } else if route == "MobileGestalt" {
                    MobileGestaltView(toolStore: toolStore)
                } else if route == "AppleWallet" {
                    AppleWalletView(walletStore: walletStore)
                } else if route == "PasscodeTheme" {
                    PasscodeThemeView(themeStore: themeStore)
                } else if route == "ThemesUI" {
                    ThemesUIView(toolStore: toolStore)
                } else if route == "zPatchCustom" {
                    zPatchCustomView()
                } else if route == "Settings" {
                    SettingsView()
                }
            }
        } // NavigationStack End
        .onChange(of: path) { newPath in
            isInNestedView.wrappedValue = !newPath.isEmpty
        }
        .onChange(of: _isSystemReady) { newValue in
            isSystemReady.wrappedValue = newValue
        }
        .onAppear {
            isSystemReady.wrappedValue = _isSystemReady
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!, .propertyList],
            onCompletion: handleFileImport
        )
        .alert("System Message", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(lastError ?? "An unknown error occurred.")
        }
        .alert("Update Available", isPresented: $showUpdateAlert) {
            Button("Cancel", role: .cancel) { ignoredUpdateBuild = pendingRemoteBuild }
            Button("Open") {
                if let url = updateURL { UIApplication.shared.open(url) }
            }
        } message: {
            Text(updateMessage)
        }
        .alert("UUID Required", isPresented: $showUUIDAlert) {
            Button("Cancel", role: .cancel) { }
            Button("OK") {
                LSApplicationWorkspaceDefaultWorkspace().openApplication(withBundleID: "com.apple.iBooks")
                
                Task {
                    do {
                        let uuid = try await BookassetdUUIDHelper.captureUUID(
                            timeout: 120,
                            openBooksFirst: false,
                            returnToAppAfterCapture: true
                        )
                        toolStore.bookassetdUUID = uuid
                        
                        DispatchQueue.main.async {
                            lastError = "UUID captured successfully! Auto-applying tweaks..."
                            showErrorAlert = true
                            
                            // Fix #3: Auto-apply after UUID fetch success
                            Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second for user to see success message
                                
                                await self.toolRunner.applyAll(isSystemReady: self._isSystemReady, store: self.toolStore, walletStore: self.walletStore, themeStore: self.themeStore)
                                
                                if case .success = self.toolRunner.state {
                                    try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds delay before respring
                                    
                                    if self.toolStore.soundRespringEnabled {
                                        try? self.respringNow()
                                    } else {
                                        if let bundleID = Bundle.main.bundleIdentifier {
                                            LSApplicationWorkspaceDefaultWorkspace().openApplication(withBundleID: bundleID)
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            lastError = "Failed to capture UUID: \(error.localizedDescription)"
                            showErrorAlert = true
                        }
                    }
                }
            }
        } message: {
            Text("Please open Books app and download a book to capture UUID. The app will automatically return and apply tweaks.")
        }
        .onAppear {
            runStartupChecksOnce()
            checkForUpdate()
            // Refresh system status (VPN, DDI, heartbeat)
            refreshSystemStatus()
            // Start network monitoring for VPN auto-refresh
            startNetworkMonitoring()
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
            if scenePhase == .active {
                autoLoadSideStorePairingIfNeeded()
                checkForUpdate()
                // Refresh system status when app becomes active
                refreshSystemStatus()
            } else if scenePhase == .background {
                // Keep network monitor running in background
            }
        }
        .onDisappear {
            // Stop network monitoring when view disappears
            stopNetworkMonitoring()
        }
    } // Body End

    // MARK: - Logic Functions

    private func isApplyRunning(_ state: ToolRunState) -> Bool {
        if case .running = state { return true }
        return false
    }

    private func applyStatusText(_ state: ToolRunState) -> String {
        if !_isSystemReady {
            if pairingFile == nil { return "Select pairing file to continue." }
            if !heartbeatRunning { return "Enable LocalDevVPN/StikDebug and reopen app." }
            if !ddiMounted { return "Mount DDI to enable tools." }
        }
        switch state {
        case .idle: return "Ready. This will run all enabled tools in order."
        case .running(let toolName): return "Running \(toolName)…"
        case .success: return "Done."
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private var appVersionFooter: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Version \(v) (\(b))"
    }

    private var currentBuildInt: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    private func runStartupChecksOnce() {
        // Fix #4 & #5: Add error handling for file operations
        
        // First, validate the pairingFile from @AppStorage if it exists
        if let existingPairingFile = pairingFile, !existingPairingFile.isEmpty {
            do {
                // Validate it can be parsed
                let _ = try PairingFileParser.parseUDID(fromPlistText: existingPairingFile)
                // Valid - keep it
            } catch {
                // Invalid pairing file in @AppStorage - clear it and show notification
                print("Removing invalid pairing file from @AppStorage: \(error.localizedDescription)")
                pairingFile = nil
                
                // Show alert to user
                DispatchQueue.main.async {
                    self.lastError = L("error_pairing_invalid_appstorage")
                    self.showErrorAlert = true
                }
                
                // Also remove from disk
                let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                try? FileManager.default.removeItem(at: pairingPath)
            }
        }
        
        // Then check disk for pairing file if @AppStorage doesn't have one
        if pairingFile == nil {
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            if FileManager.default.fileExists(atPath: pairingPath.path) {
                if let text = try? String(contentsOf: pairingPath, encoding: .utf8) {
                    // Validate the pairing file before using it
                    do {
                        let _ = try PairingFileParser.parseUDID(fromPlistText: text)
                        // Valid pairing file
                        pairingFile = text
                    } catch {
                        // Invalid pairing file - delete it and notify user
                        print("Removing invalid pairing file from disk: \(error.localizedDescription)")
                        try? FileManager.default.removeItem(at: pairingPath)
                        
                        // Show alert to user
                        DispatchQueue.main.async {
                            self.lastError = L("error_pairing_invalid_disk")
                            self.showErrorAlert = true
                        }
                    }
                }
            }
        }
        
        autoLoadSideStorePairingIfNeeded()
        
        if pairingFile != nil {
            ddiMounted = computeDDIMounted()
            startHeartbeatOnce()
        } else {
            heartbeatRunning = false
            ddiMounted = false
        }
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        if newPhase == .inactive {
            Utils.bgTask = UIApplication.shared.beginBackgroundTask {
                UIApplication.shared.endBackgroundTask(Utils.bgTask)
                Utils.bgTask = .invalid
            }
        } else if newPhase == .active {
            if Utils.bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(Utils.bgTask)
                Utils.bgTask = .invalid
            }
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // Fix #4 & #5: Add error handling for file reading
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard !text.isEmpty else {
                    lastError = "Pairing file is empty."
                    showErrorAlert = true
                    return
                }
                
                // Validate pairing file before saving
                do {
                    let _ = try PairingFileParser.parseUDID(fromPlistText: text)
                    // If we get here, the pairing file is valid
                    pairingFile = text
                    savePairingFileToDocuments(text)
                    ddiMounted = computeDDIMounted()
                    startHeartbeatOnce()
                } catch {
                    // Pairing file is invalid
                    lastError = "Invalid pairing file: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            } catch {
                lastError = "Failed to read the pairing file: \(error.localizedDescription)"
                showErrorAlert = true
            }
        case .failure(let error):
            lastError = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func autoLoadSideStorePairingIfNeeded() {
        guard pairingFile == nil else { return }
        if let altPairingFile = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String,
           altPairingFile.count > 5000 {
            // Validate before using
            do {
                let _ = try PairingFileParser.parseUDID(fromPlistText: altPairingFile)
                // Valid - use it
                pairingFile = altPairingFile
                savePairingFileToDocuments(altPairingFile)
            } catch {
                // Invalid pairing file from SideStore
                print("SideStore pairing file is invalid: \(error.localizedDescription)")
                // Don't show alert here as it might be too noisy
            }
        }
    }

    private func savePairingFileToDocuments(_ text: String) {
        // Fix #4 & #5: Add error handling for file writing
        do {
            try text.write(
                to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            // Silently handle - not critical
            print("Warning: Failed to save pairing file: \(error)")
        }
    }

    private func resetPairing() {
        pairingFile = nil
        // Fix #4 & #5: Add error handling for file deletion
        do {
            let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            if FileManager.default.fileExists(atPath: pairingPath.path) {
                try FileManager.default.removeItem(at: pairingPath)
            }
        } catch {
            print("Warning: Failed to delete pairing file: \(error)")
        }
        heartbeatRunning = false
        ddiMounted = false
    }

    private func computeDDIMounted() -> Bool {
        guard let context = JITEnableContext.shared else { return false }
        return context.isDeveloperDiskImageMounted()
    }

    private func startHeartbeatOnce() {
        guard pairingFile != nil else { return }
        DispatchQueue.global(qos: .background).async { [self] in
            let completionHandler: @convention(block) (Int32, String?) -> Void = { result, _ in
                if result == 0 {
                    DispatchQueue.main.async {
                        self.heartbeatRunning = true
                        self.ddiMounted = self.computeDDIMounted()
                        
                        // Auto-mount DDI if not mounted
                        if !self.ddiMounted {
                            self.attemptAutoMountDDI()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.heartbeatRunning = false
                        self.ddiMounted = false
                        if result == -9 {
                            self.resetPairing()
                            self.lastError = "Invalid pairing file. Please select a new one."
                        } else {
                            self.lastError = "Heartbeat failed (Error: \(result)). Enable SideStore LocalDevVPN or StikDebug, then close and reopen the app."
                        }
                        self.showErrorAlert = true
                    }
                }
            }

            guard let context = JITEnableContext.shared else {
                DispatchQueue.main.async {
                    self.heartbeatRunning = false
                    self.ddiMounted = false
                    self.lastError = "Failed to initialize JIT context. Please restart the app."
                    self.showErrorAlert = true
                }
                return
            }
            context.startHeartbeat(completionHandler: completionHandler, logger: nil)
        }
    }
    
    private func attemptAutoMountDDI() {
        guard let context = JITEnableContext.shared else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // First check if DDI is already mounted
            let currentlyMounted = self.computeDDIMounted()
            
            if currentlyMounted {
                DispatchQueue.main.async {
                    self.ddiMounted = true
                    self.lastError = "Developer Disk Image is already mounted."
                    self.showErrorAlert = true
                }
                return
            }
            
            // If not mounted, try to mount it
            do {
                try context.mountDeveloperDiskImage { status in
                    // Log on background thread to avoid excessive main queue dispatches
                    print("[DDI Auto-Mount] \(status ?? "nil")")
                }
                
                DispatchQueue.main.async {
                    // If we get here, mount succeeded
                    self.ddiMounted = self.computeDDIMounted()
                    print("[DDI Auto-Mount] Success! DDI is now mounted.")
                    
                    // Show success message to user
                    self.lastError = "Developer Disk Image mounted successfully!"
                    self.showErrorAlert = true
                }
            } catch let error as NSError {
                DispatchQueue.main.async {
                    print("[DDI Auto-Mount] Error: \(error.localizedDescription)")
                    
                    // Provide more specific guidance based on error
                    var errorMessage = "Failed to mount DDI: \(error.localizedDescription)"
                    
                    // Check if it's the FfinvalidArg error or developer mode not enabled
                    if error.code == -2 {
                        errorMessage = "Developer Mode is not enabled. Please enable it in Settings → Privacy & Security → Developer Mode, then restart your device."
                    } else if error.localizedDescription.contains("FfinvalidArg") || error.localizedDescription.contains("invalidArg") {
                        // This error typically means Developer Mode isn't properly enabled or device needs restart
                        errorMessage = "DDI mounting failed. Please ensure:\n\n1. Developer Mode is enabled in Settings → Privacy & Security → Developer Mode\n2. Your device has been restarted after enabling Developer Mode\n3. Your pairing file is valid and up-to-date\n\nIf the issue persists, Developer Disk Image may mount automatically after a device restart."
                    } else {
                        errorMessage += "\n\nFor iOS 16+: Enable Developer Mode in Settings → Privacy & Security → Developer Mode (requires restart).\n\nFor iOS 15 and older: You'll need personalized DDI files."
                    }
                    
                    self.lastError = errorMessage
                    self.showErrorAlert = true
                }
            }
        }
    }
    
    /// Refresh system status (VPN, DDI, heartbeat)
    private func refreshSystemStatus() {
        // Refresh DDI mounted status
        if pairingFile != nil {
            ddiMounted = computeDDIMounted()
        }
        // Heartbeat status is updated automatically by startHeartbeatOnce
    }
    
    /// Start network monitoring for VPN auto-refresh
    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        monitor.pathUpdateHandler = { path in
            // Check if network status changed
            DispatchQueue.main.async {
                // When network changes (VPN connects/disconnects), refresh system status
                if path.status == .satisfied {
                    // Network is available, check if we need to restart heartbeat
                    if self.pairingFile != nil && !self.heartbeatRunning {
                        self.startHeartbeatOnce()
                    }
                    self.refreshSystemStatus()
                }
            }
        }
        
        monitor.start(queue: queue)
        networkMonitor = monitor
    }
    
    /// Stop network monitoring
    private func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func respringNow() throws {
        guard let context = JITEnableContext.shared else { return }
        let processes = try getRunningProcesses()
        // Use obfuscated process path
        if let pid_backboardd = processes.first(where: { $0.value?.hasSuffix(ObfuscatedPaths.backboardd) == true })?.key {
            try context.killProcess(withPID: pid_backboardd, signal: SIGKILL)
        }
    }

    private func getRunningProcesses() throws -> [Int32 : String?] {
        // Fix #4 & #5: Add guard to prevent crashes
        guard let context = JITEnableContext.shared,
              let processList = try? context.fetchProcessList() as? [[String: Any]] else {
            return [:]
        }
        
        return Dictionary(
            uniqueKeysWithValues: processList.compactMap { item in
                guard let pid = item["pid"] as? Int32 else { return nil }
                let path = item["path"] as? String
                return (pid, path)
            }
        )
    }

    private struct RemoteVersion: Decodable {
        let version: String
        let build: Int
        let url: String
        let notes: String?
    }

    private func checkForUpdate() {
        let buildNow = currentBuildInt
        if lastCheckedBuild == buildNow { return }
        lastCheckedBuild = buildNow
        let request = URLRequest(url: versionJSONURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data else { return }
            guard let remote = try? JSONDecoder().decode(RemoteVersion.self, from: data) else { return }
            guard let url = URL(string: remote.url) else { return }
            if remote.build == ignoredUpdateBuild { return }
            if remote.build > buildNow {
                DispatchQueue.main.async {
                    pendingRemoteBuild = remote.build
                    updateURL = url
                    if let notes = remote.notes, !notes.isEmpty {
                        updateMessage = "New version \(remote.version) (\(remote.build)) is available.\n\n\(notes)"
                    } else {
                        updateMessage = "New version \(remote.version) (\(remote.build)) is available."
                    }
                    showUpdateAlert = true
                }
            }
        }.resume()
    }
}

// MARK: - Status Sheet
// MARK: - Status Sheet
struct StatusSheet: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Binding var pairingFileLoaded: Bool
    @Binding var heartbeatRunning: Bool
    @Binding var ddiMounted: Bool
    var onImportPairing: () -> Void
    var onResetPairing: () -> Void
    var onMountDDI: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.vertical, 16)

            ScrollView {
                VStack(spacing: 12) {
                    Text(L("system_status"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    CardRow(title: L("status_pairing_file"), subtitle: pairingFileLoaded ? L("status_pairing_loaded") : L("status_pairing_missing"), ok: pairingFileLoaded, showChevron: false, trailing: nil)
                        .padding(.horizontal, 20)

                    CardRow(title: L("status_heartbeat"), subtitle: heartbeatRunning ? L("status_heartbeat_running") : L("status_heartbeat_stopped"), ok: heartbeatRunning, showChevron: false, trailing: nil)
                        .padding(.horizontal, 20)

                    CardRow(title: L("status_ddi"), subtitle: ddiMounted ? L("status_ddi_mounted") : L("status_ddi_unmounted"), ok: ddiMounted, showChevron: false, trailing: nil)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }

            VStack(spacing: 12) {
                // Show Mount DDI button if heartbeat is running but DDI not mounted
                if heartbeatRunning && !ddiMounted {
                    SecondaryActionButton(title: L("button_mount_ddi"), disabled: false) {
                        onMountDDI()
                    }
                }
                
                WalletStyleButton(
                    title: pairingFileLoaded ? L("button_reset_pairing") : L("button_select_pairing"),
                    action: { if pairingFileLoaded { onResetPairing() } else { onImportPairing() }; onClose() }
                )
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .frame(height: 500)
        .background(AppTheme.bg.padding(.bottom, -100).ignoresSafeArea())
        .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: -5)
    }
}

// MARK: - Apply Sheet
struct ApplySheet: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Binding var logs: [String]
    @Binding var isRunning: Bool
    @Binding var progressText: String
    @Binding var enableRespring: Bool
    @Binding var bookassetdUUID: String
    var onApply: () -> Void
    var onClearUUID: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.vertical, 16)

            ScrollView {
                VStack(spacing: 16) {
                    Text(L("apply_tweaks"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("respring_after_apply"))
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                            Text(L("respring_desc"))
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $enableRespring).labelsHidden()
                    }
                    .padding(18)
                    .background(AppTheme.row)
                    .cornerRadius(16)
                    .padding(.horizontal, 20)

                    Text(progressText)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 4)

                    if !logs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("logs")).font(.headline).foregroundStyle(.white)
                            ForEach(logs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.vertical, 2)
                                Divider().background(Color.white.opacity(0.1))
                            }
                        }
                        .padding(18)
                        .background(AppTheme.row)
                        .cornerRadius(16)
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }

            VStack(spacing: 12) {
                SecondaryActionButton(title: L("clear_uuid"), disabled: bookassetdUUID.isEmpty) { onClearUUID() }
                WalletStyleButton(title: isRunning ? L("applying") : L("apply_enabled_tweaks"), isLoading: isRunning, disabled: isRunning) {
                    onApply()
                }
            }
            .padding(20)
            .padding(.bottom, 20)
        }
        .frame(height: 600)
        .background(AppTheme.bg.padding(.bottom, -100).ignoresSafeArea())
        .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: -5)
    }
}
