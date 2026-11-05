import SwiftUI
import UniformTypeIdentifiers

// MARK: - ThemeRowView
struct ThemeRowView: View {
    let theme: PasscodeTheme
    @ObservedObject var themeStore: PasscodeThemeStore

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = theme.getPreviewImage() {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.name).font(.headline)
                Text("\(theme.keySize.rawValue) • \(theme.telephonyVersion.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if theme.isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - ThemeDetailView
struct ThemeDetailView: View {
    @State private var theme: PasscodeTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var keySize: PasscodeTheme.KeySize
    @State private var prefix: PasscodeTheme.PrefixLanguage
    @State private var telephony: PasscodeTheme.TelephonyVersion
    @State private var showDeleteAlert = false

    init(theme: PasscodeTheme, themeStore: PasscodeThemeStore, viewModel: PasscodeThemeViewModel) {
        _theme = State(initialValue: theme)
        self.themeStore = themeStore
        self.viewModel = viewModel
        _name = State(initialValue: theme.name)
        _keySize = State(initialValue: theme.keySize)
        _prefix = State(initialValue: theme.customPrefix)
        _telephony = State(initialValue: theme.telephonyVersion)
    }

    var body: some View {
        Form {
            Section(header: Text("Preview")) {
                HStack {
                    Spacer()
                    if let img = theme.getPreviewImage() {
                        Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 160)
                    } else {
                        Text("No preview").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            Section(header: Text("Theme Info")) {
                TextField("Name", text: $name)
                Picker("Key Size", selection: $keySize) {
                    ForEach(PasscodeTheme.KeySize.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Language Prefix", selection: $prefix) {
                    ForEach(PasscodeTheme.PrefixLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Telephony Version", selection: $telephony) {
                    ForEach(PasscodeTheme.TelephonyVersion.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section {
                Button("Save Changes") { save(); dismiss() }
                Button("Select Theme") { save(); themeStore.selectTheme(theme) }
                Button(role: .destructive) { showDeleteAlert = true } label: { Text("Delete Theme") }
            }
        }
        .navigationTitle(name.isEmpty ? "Theme" : name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Theme", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { themeStore.deleteTheme(theme); dismiss() }
        } message: { Text("Delete this theme permanently?") }
    }

    private func save() {
        theme.name = name
        theme.keySize = keySize
        theme.customPrefix = prefix
        theme.telephonyVersion = telephony
        themeStore.updateTheme(theme)
    }
}

// MARK: - ImportThemeSheet
struct ImportThemeSheet: View {
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @ObservedObject var themeStore: PasscodeThemeStore
    @Environment(\.dismiss) var dismiss

    @State private var themeName = ""
    @State private var showPicker = false
    @State private var selectedFile: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Theme Name")) { TextField("My Theme", text: $themeName) }
                Section(header: Text("File")) {
                    Button("Select .passthm / ZIP") { showPicker = true }
                    if let selectedFile {
                        Text(selectedFile.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    if isImporting { ProgressView("Importing...") }
                    else {
                        Button("Import") { Task { await doImport() } }
                            .disabled(selectedFile == nil || themeName.isEmpty)
                    }
                }
            }
            .navigationTitle("Import Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [UTType.passthm, UTType(filenameExtension: "zip") ?? .data, .data]
            ) { result in
                switch result {
                case .success(let url):
                    // FIX: Copy file sang thư mục an toàn NGAY LẬP TỨC để không bị iOS thu hồi quyền
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.removeItem(at: localURL)
                        try FileManager.default.copyItem(at: url, to: localURL)
                        selectedFile = localURL
                        if themeName.isEmpty {
                            themeName = url.deletingPathExtension().lastPathComponent
                        }
                    } catch {
                        errorMessage = "Không thể đọc file: \(error.localizedDescription)"
                    }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }

    private func doImport() async {
        guard let file = selectedFile else { return }
        isImporting = true; errorMessage = nil
        do {
            try await viewModel.importTheme(from: file, name: themeName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}

// MARK: - ImportDefaultPasscodeSheet
struct ImportDefaultPasscodeSheet: View {
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @ObservedObject var themeStore: PasscodeThemeStore
    @Environment(\.dismiss) var dismiss

    @State private var showPicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Default Theme Import")) {
                    Button("Select ZIP") { showPicker = true }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    if isImporting { ProgressView("Importing...") }
                }
            }
            .navigationTitle("Import Default")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [UTType.passthm, UTType(filenameExtension: "zip") ?? .data, .data]
            ) { result in
                switch result {
                case .success(let url):
                    Task { await doImport(url) }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }

    private func doImport(_ url: URL) async {
        isImporting = true; errorMessage = nil
        defer { isImporting = false }
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: localURL)
            try FileManager.default.copyItem(at: url, to: localURL)
            
            try await viewModel.importTheme(from: localURL, name: "Default \(Int(Date().timeIntervalSince1970))")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}