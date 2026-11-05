import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation
import AirliftFFI

// MARK: - Passcode Theme View
struct PasscodeThemeView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var themeStore: PasscodeThemeStore
    @StateObject private var viewModel: PasscodeThemeViewModel
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    
    @State private var showImportSheet = false
    @State private var showDefaultImportSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSavedAlert = false
    
    // Trạng thái cho Reboot
    @State private var showResetAlert = false
    @State private var isResetting = false
    
    init(themeStore: PasscodeThemeStore) {
        self.themeStore = themeStore
        self._viewModel = StateObject(wrappedValue: PasscodeThemeViewModel(store: themeStore))
    }
    
    var body: some View {
        Form {
            Section(header: Text(L("passcode_theme_manager"))) {
                Toggle(L("passcode_enable_theme"), isOn: $themeStore.passcodeThemeEnabled)
            }
            
            // Global Settings — applies to all passcode themes
            Section(header: Text(L("global_settings"))) {
                // Language / Method
                Picker(L("passcode_language_method"), selection: $themeStore.globalCustomPrefixRaw) {
                    ForEach(PasscodeTheme.PrefixLanguage.allCases, id: \.self) { prefix in
                        Text(prefix.displayName).tag(prefix.rawValue)
                    }
                }
                
                // Telephony Version
                Picker(L("passcode_telephony_version"), selection: $themeStore.globalTelephonyVersionRaw) {
                    ForEach(PasscodeTheme.TelephonyVersion.allCases, id: \.self) { version in
                        Text(version.displayName).tag(version.rawValue)
                    }
                }
            }
            
            Section(header: Text(L("section_theme_library"))) {
                if themeStore.themes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(L("passcode_no_themes"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(themeStore.themes) { theme in
                        NavigationLink(destination: ThemeDetailView(theme: theme, themeStore: themeStore, viewModel: viewModel)) {
                            ThemeRowView(theme: theme, themeStore: themeStore)
                        }
                    }
                }
            }
            
            Section(header: Text(L("section_import_theme"))) {
                Button(L("passcode_import_file")) {
                    showImportSheet = true
                }
                
                Button(L("passcode_import_default_zip")) {
                    showDefaultImportSheet = true
                }
            }
            
            // Thêm phần Save và Reset (Reboot)
            Section {
                Button { showApplyTab = true; showSavedAlert = true } label: {
                    HStack { Image(systemName: "square.and.arrow.down"); Text("Save Changes").font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }.disabled(!themeStore.passcodeThemeEnabled)
                
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    if isResetting {
                        HStack { ProgressView(); Text("Đang khởi động lại máy...").font(.headline) }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                    } else {
                        HStack { Image(systemName: "trash"); Text("Reset Theme & Reboot").font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                }.disabled(isResetting)
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("tool_passcode_theme"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImportSheet) {
            ImportThemeSheet(viewModel: viewModel, themeStore: themeStore)
        }
        .sheet(isPresented: $showDefaultImportSheet) {
            ImportDefaultPasscodeSheet(viewModel: viewModel, themeStore: themeStore)
        }
        .alert(L("alert_error"), isPresented: $showErrorAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Tab Apply đã được mở. Chuyển sang tab Apply để áp dụng.")
        }
        .alert("Reset Theme", isPresented: $showResetAlert) {
            Button("Từ chối", role: .cancel) {}
            Button("Cho phép", role: .destructive) {
                Task { await performFullReset() }
            }
        } message: {
            Text("Máy sẽ tự khởi động lại để khởi tạo lại theme. Bạn chắc chứ?")
        }
    }
    
    private func performFullReset() async {
        isResetting = true
        defer { isResetting = false }

        themeStore.themes.removeAll()
        themeStore.passcodeThemeEnabled = false
        themeStore.saveThemes()

        let themesURL = URL.documentsDirectory.appendingPathComponent("PasscodeThemes")
        try? FileManager.default.removeItem(at: themesURL)

        let bq = BadQuery()
        let cachePaths = [
            "/var/mobile/Library/Caches/TelephonyUI-8",
            "/var/mobile/Library/Caches/TelephonyUI-9",
            "/var/mobile/Library/Caches/TelephonyUI-10"
        ]
        for path in cachePaths {
            if bq.grantAccess(atPath: path).0 {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        guard NetworkStatus.isVPNTunnelPresent() else {
            errorMessage = "VPN chưa bật. Bật VPN (SideStore/StikDebug) để khởi động lại máy."
            showErrorAlert = true
            return
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        let ok = rebootDevice()
        if !ok {
            errorMessage = "Không thể khởi động lại máy. Kiểm tra VPN và pairing file."
            showErrorAlert = true
        }
    }

    // MARK: - Real Reboot
    @discardableResult
    private func rebootDevice() -> Bool {
        do {
            try JITEnableContext.shared.killProcess(withPID: 1, signal: 9)
            return true
        } catch {
            NSLog("[Reboot] killProcess(withPID: 1, SIGKILL) failed: \(error.localizedDescription)")
        }

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        if FileManager.default.fileExists(atPath: pairingURL.path) {
            var errPtr: UnsafeMutablePointer<CChar>? = nil
            let res = al_device_respring(pairingURL.path, nil, nil, &errPtr)
            if let e = errPtr { al_string_free(e) }
            if res == 0 { return true }
        }

        try? RespringHelper.respring()
        return false
    }
}