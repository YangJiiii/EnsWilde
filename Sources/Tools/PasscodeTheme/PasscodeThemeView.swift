import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

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
    @State private var showResetAlert = false

    init(themeStore: PasscodeThemeStore) {
        self.themeStore = themeStore
        self._viewModel = StateObject(wrappedValue: PasscodeThemeViewModel(store: themeStore))
    }

    var body: some View {
        Form {
            Section(header: Text(L("passcode_theme_manager"))) {
                Toggle(L("passcode_enable_theme"), isOn: $themeStore.passcodeThemeEnabled)
            }
            Section(header: Text(L("global_settings"))) {
                Picker(L("passcode_language_method"), selection: $themeStore.globalCustomPrefixRaw) {
                    ForEach(PasscodeTheme.PrefixLanguage.allCases, id: \.self) { prefix in Text(prefix.displayName).tag(prefix.rawValue) }
                }
                Picker(L("passcode_telephony_version"), selection: $themeStore.globalTelephonyVersionRaw) {
                    ForEach(PasscodeTheme.TelephonyVersion.allCases, id: \.self) { version in Text(version.displayName).tag(version.rawValue) }
                }
            }
            Section(header: Text(L("section_theme_library"))) {
                if themeStore.themes.isEmpty {
                    emptyThemeState
                } else {
                    ForEach(themeStore.themes) { theme in
                        NavigationLink(destination: ThemeDetailView(theme: theme, themeStore: themeStore, viewModel: viewModel)) {
                            ThemeRowView(theme: theme, themeStore: themeStore)
                        }
                    }
                }
            }
            Section(header: Text(L("section_import_theme"))) {
                Button(L("passcode_import_file")) { showImportSheet = true }
                Button(L("passcode_import_default_zip")) { showDefaultImportSheet = true }
            }
            Section {
                Button { showApplyTab = true; showSavedAlert = true } label: {
                    HStack { Image(systemName: "square.and.arrow.down"); Text("Save Changes").font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }.disabled(!themeStore.passcodeThemeEnabled)
                
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    HStack { Image(systemName: "trash"); Text("Reset Theme").font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("tool_passcode_theme"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImportSheet) { ImportThemeSheet(viewModel: viewModel, themeStore: themeStore) }
        .sheet(isPresented: $showDefaultImportSheet) { ImportDefaultPasscodeSheet(viewModel: viewModel, themeStore: themeStore) }
        .alert(L("alert_error"), isPresented: $showErrorAlert) { Button(L("alert_ok")) {} } message: { Text(errorMessage) }
        .alert("Saved", isPresented: $showSavedAlert) { Button("OK") {} } message: { Text("Tab Apply đã được mở. Chuyển sang tab Apply để áp dụng.") }
        .alert("Reset Theme", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetAllThemes()
            }
        } message: {
            Text("Are you sure you want to delete all themes and reset to default?")
        }
    }

    private var emptyThemeState: some View {
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
    }
    
    private func resetAllThemes() {
        themeStore.themes.removeAll()
        themeStore.passcodeThemeEnabled = false
        themeStore.saveThemes()
        
        let themesURL = URL.documentsDirectory.appendingPathComponent("PasscodeThemes")
        try? FileManager.default.removeItem(at: themesURL)
    }
}