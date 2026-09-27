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
    
    // Pairing file replacement confirmation
    @State private var showPairingReplaceConfirm = false
    @State private var pendingPairingFileText: String?
    
    // Binding for external control of apply sheet (default to internal state)
    var showApplySheetBinding: Binding<Bool>? = nil
    var showStatusSheetBinding: Binding<Bool>? = nil
    
    // Hide the bottom Apply button when using navigation bar
    var hideBottomApplyButton: Bool = false
    
    // Optional bindings to track navigation state
    var isInNestedViewBinding: Binding<Bool>?
    var isSystemReadyBinding: Binding<Bool>?
    var heartbeatRunningBinding: Binding<Bool>?
    var ddiMountedBinding: Binding<Bool>?
    
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

    // Tools (shared from MainViewWithNavigation)
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore

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
    
    // Auto-reset pairing file when not ready
    @State private var pairingResetTimer: DispatchWorkItem?
    @State private var pairingResetAttempted = false
    
    // DDI monitoring and auto-remount
    @State private var ddiMonitorTimer: Timer?
    @State private var lastKnownDDIMountState = false
    @State private var ddiMountRetryCount = 0
    @State private var lastDDIMountAttempt: Date?
    
    // Animation Config (Hiệu ứng trượt mượt mà)
    private let panelAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    
    // Custom initializer to accept optional bindings
    init(
        themeStore: PasscodeThemeStore,
        toolStore: ToolStore,
        toolRunner: ToolRunner,
        featureFlagsStore: FeatureFlagsStore,
        showApplySheetBinding: Binding<Bool>? = nil,
        showStatusSheetBinding: Binding<Bool>? = nil,
        hideBottomApplyButton: Bool = false,
        isInNestedViewBinding: Binding<Bool>? = nil,
        isSystemReadyBinding: Binding<Bool>? = nil,
        heartbeatRunningBinding: Binding<Bool>? = nil,
        ddiMountedBinding: Binding<Bool>? = nil
    ) {
        self.themeStore = themeStore
        self.toolStore = toolStore
        self.toolRunner = toolRunner
        self.featureFlagsStore = featureFlagsStore
        self.showApplySheetBinding = showApplySheetBinding
        self.showStatusSheetBinding = showStatusSheetBinding
        self.hideBottomApplyButton = hideBottomApplyButton
        self.isInNestedViewBinding = isInNestedViewBinding
        self.isSystemReadyBinding = isSystemReadyBinding
        self.heartbeatRunningBinding = heartbeatRunningBinding
        self.ddiMountedBinding = ddiMountedBinding
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                statusSection
                tweaksSection
            }
            .headerProminence(.increased)
            .navigationTitle("EnsWilde")
            .navigationDestination(for: String.self) { route in
                destinationView(for: route)
            }
        } // NavigationStack End
        .onChange(of: path) { newPath in
            isInNestedView.wrappedValue = !newPath.isEmpty
        }
        .onChange(of: _isSystemReady) { newValue in
            isSystemReady.wrappedValue = newValue
        }
        .onChange(of: heartbeatRunning) { newValue in
            heartbeatRunningBinding?.wrappedValue = newValue
        }
        .onChange(of: ddiMounted) { newValue in
            ddiMountedBinding?.wrappedValue = newValue
        }
        .onAppear {
            isSystemReady.wrappedValue = _isSystemReady
            heartbeatRunningBinding?.wrappedValue = heartbeatRunning
            ddiMountedBinding?.wrappedValue = ddiMounted
        }
        .sheet(isPresented: statusSheet) {
            statusSheetContent
        }
        .sheet(isPresented: showApplySheet) {
            applySheetContent
        }
        .fileImporter(
            isPresented: $showPairingFileImporter,
            allowedContentTypes: [
                .propertyList,
                UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!
            ],
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
                handleUUIDCapture()
            }
        } message: {
            Text("Please open Books app and download a book to capture UUID. The app will automatically return and apply tweaks.")
        }
        .alert("Replace Existing Pairing File?", isPresented: $showPairingReplaceConfirm) {
            Button("Cancel", role: .cancel) {
                pendingPairingFileText = nil
            }
            Button("Replace", role: .destructive) {
                if let text = pendingPairingFileText {
                    importPairingFile(text)
                }
                pendingPairingFileText = nil
            }
        } message: {
            Text("You already have a pairing file loaded. Do you want to replace it with the new one? This will restart the connection.")
        }
        .onAppear {
            runStartupChecksOnce()
            checkForUpdate()
            refreshSystemStatus()
            startNetworkMonitoring()
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
            if scenePhase == .active {
                autoLoadSideStorePairingIfNeeded()
                checkForUpdate()
                refreshSystemStatus()
                if pairingFile != nil && !_isSystemReady {
                    startPairingResetTimer()
                }
            } else if scenePhase == .background {
                cancelPairingResetTimer()
            }
        }
        .onChange(of: heartbeatRunning) {
            if heartbeatRunning {
                print("[Auto-Reset] Heartbeat running, canceling timer")
                cancelPairingResetTimer()
            }
        }
        .onChange(of: _isSystemReady) {
            if _isSystemReady {
                print("[Auto-Reset] System ready, canceling timer")
                cancelPairingResetTimer()
                pairingResetAttempted = false
            } else if pairingFile != nil {
                startPairingResetTimer()
            }
        }
        .onChange(of: pairingFile) {
            pairingResetAttempted = false
            if pairingFile == nil {
                cancelPairingResetTimer()
            }
        }
        .onDisappear {
            stopNetworkMonitoring()
            stopDDIMonitoring()
            cancelPairingResetTimer()
        }
    } // Body End

    // MARK: - Body Sections

    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text(L("section_status"))) {
            CardRow(
                title: L("system_status"),
                subtitle: _isSystemReady ? L("system_status_ready") : L("system_status_not_ready"),
                ok: _isSystemReady,
                showChevron: false,
                trailing: nil
            )

            if pairingFile == nil {
                Button(action: { showPairingFileImporter = true }) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("pairing_file_missing"))
                            Text(L("pairing_file_import_prompt"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if !heartbeatRunning && pairingFile != nil {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("heartbeat_not_running"))
                        Text(L("heartbeat_enable_vpn"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }

            if !ddiMounted && pairingFile != nil && heartbeatRunning {
                ddiStatusLabel
            }
        }
    }

    @ViewBuilder
    private var ddiStatusLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("ddi_not_mounted"))
                if ddiMountRetryCount >= 5 {
                    Text("Max auto-mount attempts reached. Tap status bar to retry manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if ddiMountRetryCount > 0 {
                    Text("Auto-mounting DDI... (Attempt \(ddiMountRetryCount)/5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("ddi_auto_mount_attempt"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: ddiMountRetryCount >= 5 ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var tweaksSection: some View {
        Section(header: Text(L("section_tweaks"))) {
            toolNavigationLink(
                value: "MobileGestalt",
                title: L("tool_mobile_gestalt"),
                subtitle: L("tool_mobile_gestalt_desc"),
                icon: "cpu",
                isEnabled: toolStore.replaceMobileGestaltEnabled
            )

            toolNavigationLink(
                value: "ThemesUI",
                title: L("tool_themes_ui"),
                subtitle: L("tool_themes_ui_desc"),
                icon: "paintbrush",
                isEnabled: toolStore.themesUIEnabled
            )

            toolNavigationLink(
                value: "PasscodeTheme",
                title: L("tool_passcode_theme"),
                subtitle: L("tool_passcode_theme_desc"),
                icon: "lock.rectangle",
                isEnabled: themeStore.passcodeThemeEnabled
            )

            toolNavigationLink(
                value: "FeatureFlags",
                title: L("tool_feature_flags"),
                subtitle: L("tool_feature_flags_desc"),
                icon: "flag",
                isEnabled: featureFlagsStore.featureFlagsEnabled
            )
        }
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func destinationView(for route: String) -> some View {
        if route == "MobileGestalt" {
            MobileGestaltView(toolStore: toolStore)
        } else if route == "PasscodeTheme" {
            PasscodeThemeView(themeStore: themeStore)
        } else if route == "ThemesUI" {
            ThemesUIView(toolStore: toolStore)
        } else if route == "FeatureFlags" {
            FeatureFlagsView(store: featureFlagsStore)
        }
    }

    // MARK: - Sheet Contents

    private var statusSheetContent: some View {
        StatusSheet(
            pairingFileLoaded: .constant(pairingFile != nil),
            heartbeatRunning: $heartbeatRunning,
            ddiMounted: $ddiMounted,
            onImportPairing: { showPairingFileImporter = true },
            onResetPairing: { resetPairing() },
            onMountDDI: { attemptAutoMountDDI() },
            onClose: { statusSheet.wrappedValue = false }
        )
        .presentationDetents([.medium, .large])
    }

    private var applySheetContent: some View {
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
                    
                    await toolRunner.applyAll(isSystemReady: _isSystemReady, store: toolStore, themeStore: themeStore, featureFlagsStore: featureFlagsStore)
                    
                    if case .success = toolRunner.state {
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        
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
            onClose: { showApplySheet.wrappedValue = false }
        )
        .presentationDetents([.large])
    }

    // MARK: - UUID Capture

    private func handleUUIDCapture() {
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
                    
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        
                        await self.toolRunner.applyAll(isSystemReady: self._isSystemReady, store: self.toolStore, themeStore: self.themeStore, featureFlagsStore: self.featureFlagsStore)
                        
                        if case .success = self.toolRunner.state {
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            
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

    // MARK: - Tool Navigation Link (Feather-style)

    @ViewBuilder
    private func toolNavigationLink(value: String, title: String, subtitle: String, icon: String, isEnabled: Bool) -> some View {
        NavigationLink(value: value) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } icon: {
                    Image(systemName: icon)
                }
                Spacer()
                if isEnabled {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }

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
            // Start auto-reset timer if system not ready
            startPairingResetTimer()
        } else {
            heartbeatRunning = false
            ddiMounted = false
            cancelPairingResetTimer()
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
                
                // Validate pairing file before proceeding
                do {
                    let _ = try PairingFileParser.parseUDID(fromPlistText: text)
                    // If we get here, the pairing file is valid
                    
                    // Check if user already has a pairing file loaded
                    if pairingFile != nil {
                        // Show confirmation dialog before replacing
                        pendingPairingFileText = text
                        showPairingReplaceConfirm = true
                    } else {
                        // No existing pairing file, import directly
                        importPairingFile(text)
                    }
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
    
    /// Import and activate a pairing file
    private func importPairingFile(_ text: String) {
        pairingFile = text
        savePairingFileToDocuments(text)
        ddiMounted = computeDDIMounted()
        startHeartbeatOnce()
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
        
        // Stop DDI monitoring
        stopDDIMonitoring()
        
        // Reset DDI state
        lastKnownDDIMountState = false
        ddiMountRetryCount = 0
        lastDDIMountAttempt = nil
    }
    
    /// Start timer to auto-reset pairing file if system not ready after 3 seconds
    private func startPairingResetTimer() {
        // Cancel any existing timer
        cancelPairingResetTimer()
        
        // Only start timer if:
        // 1. Pairing file exists
        // 2. System is not ready
        // 3. Haven't already attempted reset for this pairing file
        guard pairingFile != nil && !_isSystemReady && !pairingResetAttempted else {
            return
        }
        
        print("[Auto-Reset] Starting 3-second timer for pairing validation")
        
        let workItem = DispatchWorkItem {
            // Double-check conditions before resetting
            if self.pairingFile != nil && !self._isSystemReady {
                print("[Auto-Reset] System not ready after 3 seconds, resetting pairing file")
                
                DispatchQueue.main.async {
                    self.pairingResetAttempted = true
                    self.resetPairing()
                    
                    // Show error alert
                    self.lastError = "Pairing file is invalid or LocalDev VPN is not enabled. Please check:\n- SideStore LocalDevVPN or StikDebug is running\n- VPN connection is active\n- Pairing file is valid\nThen import a new pairing file."
                    self.showErrorAlert = true
                }
            }
        }
        
        pairingResetTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }
    
    /// Cancel the auto-reset timer
    private func cancelPairingResetTimer() {
        pairingResetTimer?.cancel()
        pairingResetTimer = nil
    }

    private func computeDDIMounted() -> Bool {
        guard let context = JITEnableContext.shared else { return false }
        return context.isDeveloperDiskImageMounted()
    }

    private func startHeartbeatOnce() {
        guard pairingFile != nil else { return }
        DispatchQueue.global(qos: .background).async { [self] in
            let completionHandler: @convention(block) (Int32, String?) -> Void = { result, message in
                DispatchQueue.main.async {
                    if result == 0 {
                        self.heartbeatRunning = true
                        self.ddiMounted = self.computeDDIMounted()
                        self.lastKnownDDIMountState = self.ddiMounted
                        
                        // Start DDI monitoring
                        self.startDDIMonitoring()
                        
                        // Auto-mount DDI if not mounted
                        if !self.ddiMounted {
                            self.attemptAutoMountDDI()
                        }
                    } else {
                        self.heartbeatRunning = false
                        self.ddiMounted = false
                        
                        // Stop DDI monitoring when heartbeat fails
                        self.stopDDIMonitoring()
                        
                        // Provide specific error messages based on error code
                        switch result {
                        case -9:
                            self.resetPairing()
                            self.lastError = "Invalid pairing file. Please select a new one."
                        case -1:
                            self.lastError = "Connection failed. Please check:\n- SideStore LocalDevVPN or StikDebug is running\n- VPN connection is active\n- Then close and reopen the app"
                        case -2:
                            self.lastError = "No valid tunnel IPs found. Please configure TunnelDeviceIP in settings or ensure VPN is properly set up."
                        default:
                            let errorMsg = message ?? "Unknown error"
                            self.lastError = "Heartbeat failed (Error: \(result)): \(errorMsg)"
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
            
            // Call startHeartbeat with proper error handling
            context.startHeartbeat(completionHandler: completionHandler, logger: { msg in
                print("[Heartbeat] \(msg)")
            })
        }
    }
    
    private func attemptAutoMountDDI(showErrorAlert: Bool = true) {
        guard let context = JITEnableContext.shared else { return }
        
        // If this is a manual attempt (showErrorAlert = true), reset the retry counter
        if showErrorAlert && ddiMountRetryCount >= 5 {
            print("[DDI Manual Mount] Resetting stuck retry counter for manual attempt")
            ddiMountRetryCount = 0
            lastDDIMountAttempt = nil
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // First check if DDI is already mounted
            let currentlyMounted = self.computeDDIMounted()
            
            if currentlyMounted {
                DispatchQueue.main.async {
                    self.ddiMounted = true
                    if showErrorAlert {
                        self.lastError = "Developer Disk Image is already mounted."
                        self.showErrorAlert = true
                    }
                }
                return
            }
            
            // If not mounted, try built-in DDI first
            do {
                try context.mountDeveloperDiskImage { status in
                    print("[DDI Auto-Mount] \(status ?? "nil")")
                }
                
                DispatchQueue.main.async {
                    self.ddiMounted = self.computeDDIMounted()
                    self.lastKnownDDIMountState = self.ddiMounted
                    self.ddiMountRetryCount = 0
                    print("[DDI Auto-Mount] Success! DDI is now mounted.")
                    
                    if showErrorAlert {
                        self.lastError = "Developer Disk Image mounted successfully!"
                        self.showErrorAlert = true
                    }
                }
            } catch let error as NSError {
                print("[DDI Auto-Mount] Built-in DDI failed: \(error.localizedDescription). Trying personalized DDI...")
                
                // Fallback: try personalized DDI if files are downloaded
                let imagePath = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg").path
                let trustcachePath = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path
                let manifestPath = URL.documentsDirectory.appendingPathComponent("DDI/BuildManifest.plist").path
                let fm = FileManager.default
                
                if fm.fileExists(atPath: imagePath) && fm.fileExists(atPath: trustcachePath) && fm.fileExists(atPath: manifestPath) {
                    do {
                        try context.mountPersonalDDI(withImagePath: imagePath, trustcachePath: trustcachePath, manifestPath: manifestPath)
                        
                        DispatchQueue.main.async {
                            self.ddiMounted = self.computeDDIMounted()
                            self.lastKnownDDIMountState = self.ddiMounted
                            self.ddiMountRetryCount = 0
                            print("[DDI Auto-Mount] Personalized DDI mounted successfully!")
                            
                            if showErrorAlert {
                                self.lastError = L("ddi_mount_personal_success")
                                self.showErrorAlert = true
                            }
                        }
                        return
                    } catch let personalError as NSError {
                        print("[DDI Auto-Mount] Personalized DDI also failed: \(personalError.localizedDescription)")
                    }
                }
                
                DispatchQueue.main.async {
                    print("[DDI Auto-Mount] Error: \(error.localizedDescription)")
                    
                    if showErrorAlert {
                        var errorMessage = "Failed to mount DDI: \(error.localizedDescription)"
                        
                        if error.code == -2 {
                            errorMessage = "Developer Mode is not enabled. Please enable it in Settings → Privacy & Security → Developer Mode, then restart your device."
                        } else if error.localizedDescription.contains("FfinvalidArg") || error.localizedDescription.contains("invalidArg") {
                            errorMessage = "DDI mounting failed. This can happen after device reboot.\n\nPlease try:\n1. Go to Settings tab → Download DDI → Mount Personalized DDI\n2. Or enable Developer Mode in Settings → Privacy & Security → Developer Mode\n3. Wait a moment and the app will retry automatically"
                        } else {
                            errorMessage += "\n\nTip: Go to Settings tab → Download DDI to download personalized DDI files, then use Mount Personalized DDI."
                        }
                        
                        self.lastError = errorMessage
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }
    
    /// Refresh system status (VPN, DDI, heartbeat)
    private func refreshSystemStatus() {
        // Refresh DDI mounted status
        if pairingFile != nil {
            let newDDIState = computeDDIMounted()
            
            // Check if DDI state changed
            if newDDIState != ddiMounted {
                print("[Refresh] DDI state changed: \(ddiMounted) -> \(newDDIState)")
                ddiMounted = newDDIState
                lastKnownDDIMountState = newDDIState
                
                // If DDI became unmounted, attempt to remount
                if !newDDIState && heartbeatRunning {
                    print("[Refresh] DDI unmounted, attempting remount...")
                    // Reset retry counter on network change/refresh
                    if ddiMountRetryCount >= 5 {
                        print("[Refresh] Resetting stuck retry counter (was at max)")
                        ddiMountRetryCount = 0
                        lastDDIMountAttempt = nil
                    }
                    attemptAutoMountDDIWithRetry()
                } else if newDDIState {
                    // DDI mounted successfully - reset counter
                    ddiMountRetryCount = 0
                    lastDDIMountAttempt = nil
                }
            } else {
                ddiMounted = newDDIState
            }
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