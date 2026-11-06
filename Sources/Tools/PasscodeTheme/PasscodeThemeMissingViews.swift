import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - PasscodeFileImporterView (Đã đổi tên để không bị trùng với Wallet)
struct PasscodeFileImporterView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let allowedTypes: [UTType]
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: PasscodeFileImporterView
        init(_ parent: PasscodeFileImporterView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onPick(url)
            }
            parent.isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Theme Row View
struct ThemeRowView: View {
    let theme: PasscodeTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    
    var body: some View {
        HStack(spacing: 12) {
            if let previewImage = theme.getPreviewImage() {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.name).font(.body)
                Text("\(theme.keySize.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: theme.isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(theme.isSelected ? .green : .secondary)
                .onTapGesture {
                    themeStore.selectTheme(theme)
                }
        }
    }
}

// MARK: - Theme Detail View
struct ThemeDetailView: View {
    @State var theme: PasscodeTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @State private var showDeleteAlert = false
    @State private var showFullPreview = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            Section(header: Text(L("section_preview"))) {
                if let previewImage = theme.getPreviewImage() {
                    VStack(spacing: 12) {
                        Image(uiImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 120)
                            .cornerRadius(12)
                        
                        Button {
                            showFullPreview = true
                        } label: {
                            HStack {
                                Image(systemName: "eye.fill")
                                Text(L("passcode_view_all_keys"))
                            }
                        }
                    }
                }
            }
            
            Section(header: Text(L("section_theme_settings"))) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("passcode_theme_name")).font(.caption).foregroundStyle(.secondary)
                    TextField(L("passcode_theme_name"), text: $theme.name)
                        .onChange(of: theme.name) { _, _ in themeStore.updateTheme(theme) }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("passcode_detected_size")).font(.caption).foregroundStyle(.secondary)
                        Text(sizeDescription(for: theme.detectedSize))
                    }
                    Spacer()
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("passcode_target_key_size")).font(.caption).foregroundStyle(.secondary)
                    Picker("Key Size", selection: $theme.keySize) {
                        ForEach(PasscodeTheme.KeySize.allCases, id: \.self) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: theme.keySize) { _, _ in themeStore.updateTheme(theme) }
                    
                    Text(scalingDescription(from: theme.detectedSize, to: theme.keySize)).font(.caption).foregroundStyle(.secondary)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("passcode_selected_theme"))
                        Text(theme.isSelected ? L("passcode_theme_selected") : L("passcode_theme_not_selected"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        themeStore.selectTheme(theme)
                        theme.isSelected = true
                    } label: {
                        Text(theme.isSelected ? L("passcode_selected") : L("passcode_select"))
                            .foregroundStyle(theme.isSelected ? .green : .accentColor)
                    }
                }
            }
            
            Section(header: Text(L("section_theme_files"))) {
                let imageFiles = theme.getImageFiles()
                Text("\(imageFiles.count) image file(s) found").foregroundStyle(.secondary)
            }
            
            Section(header: Text(L("section_danger_zone"))) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Text(L("passcode_delete_theme"))
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(theme.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFullPreview) {
            FullPasscodePreviewSheet(theme: theme)
        }
        .alert(L("passcode_delete_theme"), isPresented: $showDeleteAlert) {
            Button(L("alert_cancel"), role: .cancel) {}
            Button(L("alert_delete"), role: .destructive) {
                themeStore.deleteTheme(theme)
                dismiss()
            }
        } message: {
            Text(L("passcode_delete_confirm"))
        }
    }
    
    private func sizeDescription(for detectedSize: PasscodeTheme.DetectedSize) -> String {
        switch detectedSize {
        case .small: return "Small Keys (202px)"
        case .big: return "Big Keys (287px)"
        case .unknown: return "Unknown (will use target size)"
        }
    }
    
    private func scalingDescription(from detectedSize: PasscodeTheme.DetectedSize, to targetSize: PasscodeTheme.KeySize) -> String {
        if detectedSize == .unknown {
            return "No scaling info available - images will be used as-is"
        } else if (detectedSize == .small && targetSize == .big) {
            return "Will scale up from small to big (×1.42)"
        } else if (detectedSize == .big && targetSize == .small) {
            return "Will scale down from big to small (×0.70)"
        } else {
            return "No scaling needed - sizes match"
        }
    }
}

// MARK: - Import Theme Sheet
struct ImportThemeSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @ObservedObject var themeStore: PasscodeThemeStore
    @State private var themeName = ""
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                if let url = selectedFileURL {
                    Section {
                        Text(L("file_selected").replacingOccurrences(of: "{name}", with: url.lastPathComponent))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section(header: Text(L("theme_information"))) {
                    TextField(L("passcode_theme_name"), text: $themeName)
                        .autocorrectionDisabled()
                }
                
                Section {
                    Button(L("select_file")) { showFilePicker = true }
                }
                
                if isImporting {
                    Section { ProgressView(L("importing")) }
                }
            }
            .navigationTitle(L("section_import_theme"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_import")) { importTheme() }
                    .disabled(themeName.isEmpty || selectedFileURL == nil || isImporting)
                }
            }
            .sheet(isPresented: $showFilePicker) {
                // Dùng PasscodeFileImporterView đã đổi tên
                PasscodeFileImporterView(isPresented: $showFilePicker, allowedTypes: [.item, .data, .zip]) { url in
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: tempURL)
                    try? FileManager.default.copyItem(at: url, to: tempURL)
                    
                    selectedFileURL = tempURL
                    if themeName.isEmpty {
                        themeName = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
            .alert(L("alert_error"), isPresented: .constant(errorMessage != nil)) {
                Button(L("alert_ok")) { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
        }
    }
    
    private func importTheme() {
        guard let url = selectedFileURL else { return }
        isImporting = true
        Task {
            do {
                try await viewModel.importTheme(from: url, name: themeName)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Import Default Passcode Sheet
struct ImportDefaultPasscodeSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @ObservedObject var themeStore: PasscodeThemeStore
    @State private var themeName = ""
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var detectedInfo = ""
    
    var body: some View {
        NavigationStack {
            Form {
                if let url = selectedFileURL {
                    Section {
                        Text(L("file_selected").replacingOccurrences(of: "{name}", with: url.lastPathComponent))
                            .foregroundStyle(.secondary)
                        if !detectedInfo.isEmpty {
                            Text(detectedInfo).font(.caption).foregroundStyle(.green)
                        }
                    }
                }
                
                Section(header: Text(L("theme_information"))) {
                    TextField(L("passcode_theme_name"), text: $themeName).autocorrectionDisabled()
                }
                
                Section {
                    Button(L("passcode_select_zip")) { showFilePicker = true }
                }
                
                if isImporting {
                    Section { ProgressView(L("importing")) }
                }
            }
            .navigationTitle(L("passcode_import_default_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("alert_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("alert_import")) { importDefaultPasscode() }
                    .disabled(themeName.isEmpty || selectedFileURL == nil || isImporting)
                }
            }
            .sheet(isPresented: $showFilePicker) {
                // Dùng PasscodeFileImporterView đã đổi tên
                PasscodeFileImporterView(isPresented: $showFilePicker, allowedTypes: [.item, .data, .zip]) { url in
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: tempURL)
                    try? FileManager.default.copyItem(at: url, to: tempURL)
                    
                    selectedFileURL = tempURL
                    if themeName.isEmpty {
                        themeName = url.deletingPathExtension().lastPathComponent
                    }
                    previewZIPContents(url: tempURL)
                }
            }
            .alert(L("alert_error"), isPresented: .constant(errorMessage != nil)) {
                Button(L("alert_ok")) { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
        }
    }
    
    private func previewZIPContents(url: URL) {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return }
        var telephonyFolder: String?
        var languageCode: String?
        
        for entry in archive {
            let path = entry.path
            let components = path.split(separator: "/")
            for comp in components {
                let compStr = String(comp)
                if compStr.hasPrefix("Telephony") { telephonyFolder = compStr }
            }
            if languageCode == nil {
                let filename = (path as NSString).lastPathComponent
                let ext = (filename as NSString).pathExtension.lowercased()
                if ext == "png" || ext == "jpg" || ext == "jpeg" {
                    if let firstHyphen = filename.firstIndex(of: "-") {
                        let prefix = String(filename[filename.startIndex..<firstHyphen])
                        if !prefix.isEmpty { languageCode = prefix }
                    }
                }
            }
        }
        
        var info: [String] = []
        if let tf = telephonyFolder { info.append("Telephony: \(tf)") }
        if let lc = languageCode { info.append("Language: \(lc)") }
        detectedInfo = info.joined(separator: " • ")
    }
    
    private func importDefaultPasscode() {
        guard let url = selectedFileURL else { return }
        isImporting = true
        Task {
            do {
                try await viewModel.importDefaultPasscode(from: url, name: themeName, themeStore: themeStore)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Full Passcode Preview Sheet
struct FullPasscodePreviewSheet: View {
    let theme: PasscodeTheme
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("passcode_all_keys_from").replacingOccurrences(of: "{name}", with: theme.name))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                let keyImages = getAllPasscodeKeyImages()
                if keyImages.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundStyle(.secondary)
                            Text(L("passcode_no_key_images")).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                } else {
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(keyImages, id: \.key) { item in
                                if item.key == "empty" {
                                    Color.clear.frame(maxWidth: 100, maxHeight: 100)
                                } else {
                                    VStack(spacing: 6) {
                                        Image(uiImage: item.image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 100, maxHeight: 100).cornerRadius(8)
                                        Text(item.label).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .headerProminence(.increased)
            .navigationTitle(L("passcode_all_keys"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("alert_done")) { dismiss() } }
            }
        }
    }
    
    private func getAllPasscodeKeyImages() -> [(key: String, label: String, image: UIImage)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: theme.themeFolderURL.path) else { return [] }
        var keyImages: [(String, String, UIImage)] = []
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "empty", "0", "empty"]
        let labels = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", ""]
        
        for (index, key) in keys.enumerated() {
            if key == "empty" {
                keyImages.append((key, labels[index], UIImage()))
                continue
            }
            if let file = files.first(where: { $0.lowercased().contains("-\(key)-") || $0.lowercased().contains("-\(key)@") || $0.lowercased().contains("_\(key)_") || $0.lowercased().contains("_\(key)@") }) {
                let imageURL = theme.themeFolderURL.appendingPathComponent(file)
                if let image = UIImage(contentsOfFile: imageURL.path) {
                    keyImages.append((key, labels[index], image))
                }
            }
        }
        return keyImages
    }
}