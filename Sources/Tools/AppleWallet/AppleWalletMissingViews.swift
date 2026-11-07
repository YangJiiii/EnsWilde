import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - WalletCardPreview (Giao diện ngoài danh sách)
struct WalletCardPreview: View {
    let card: AppleWalletCard
    let index: Int
    let total: Int
    @ObservedObject var walletStore: AppleWalletStore

    private var displayName: String {
        if let suffix = card.getPrimaryAccountSuffix(), !suffix.isEmpty {
            return "Card •••• \(suffix)"
        }
        return card.name
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let data = card.backgroundImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [.blue, .purple],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 84, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName).font(.headline)
                Text(card.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { card.enabled },
                set: { newVal in
                    var updated = card
                    updated.enabled = newVal
                    walletStore.updateCard(updated)
                }
            )).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AppleWalletCardDetailView (Giao diện sửa Card)
struct AppleWalletCardDetailView: View {
    @State private var card: AppleWalletCard
    @ObservedObject var walletStore: AppleWalletStore
    @Environment(\.dismiss) var dismiss

    @State private var cardName: String
    @State private var enabled: Bool
    @State private var primaryAccountSuffix: String
    @State private var hasPassJSON: Bool

    @State private var cardImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showDeleteAlert = false

    init(card: AppleWalletCard, walletStore: AppleWalletStore) {
        _card = State(initialValue: card)
        self.walletStore = walletStore
        _cardName = State(initialValue: card.name)
        _enabled = State(initialValue: card.enabled)
        _primaryAccountSuffix = State(initialValue: card.getPrimaryAccountSuffix() ?? "")
        _hasPassJSON = State(initialValue: card.hasPassJSON)
        
        // Ưu tiên load backgroundImage, nếu không có thì load previewImage
        let imgData = card.backgroundImageData ?? card.previewImageData
        _cardImage = State(initialValue: imgData.flatMap(UIImage.init(data:)))
    }

    var body: some View {
        Form {
            Section(header: Text("Card Info")) {
                TextField("Card Name", text: $cardName)
                Text("ID: \(card.id)").font(.caption).foregroundStyle(.secondary)
                
                // Thêm ô nhập số cuối thẻ (8390)
                if hasPassJSON {
                    HStack {
                        Text("Last 4 Digits")
                        Spacer()
                        TextField("8390", text: $primaryAccountSuffix)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }
                
                Toggle("Enabled", isOn: $enabled)
            }

            Section(header: Text("Card Image (Preview)")) {
                Button {
                    showPicker = true
                } label: {
                    if let cardImage {
                        Image(uiImage: cardImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Tap to select card image")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                Button("Save Changes") { saveAll(); dismiss() }
                Button(role: .destructive) { showDeleteAlert = true } label: { Text("Delete Card") }
            }
        }
        .navigationTitle(cardName.isEmpty ? "Card" : cardName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Card", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                walletStore.deleteCard(card); dismiss()
            }
        } message: { Text("Delete this card permanently?") }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    await MainActor.run {
                        cardImage = ui
                        pickerItem = nil
                    }
                }
            }
        }
    }

    private func saveAll() {
        card.name = cardName
        card.enabled = enabled
        
        if let cardImage {
            // Gán 1 ảnh này cho cả 3 vị trí để thẻ hiển thị đẹp nhất
            let data = cardImage.pngData()
            card.backgroundImageData = data
            card.previewImageData = data
            card.frontFaceImageData = data
            card.placeHolderImageData = data
        }
        
        if hasPassJSON {
            card.setPrimaryAccountSuffix(primaryAccountSuffix)
        }
        walletStore.updateCard(card)
    }
}

// MARK: - ManualAddCardSheet
struct ManualAddCardSheet: View {
    @ObservedObject var walletStore: AppleWalletStore
    @Environment(\.dismiss) var dismiss
    @State private var cardID = ""
    @State private var cardName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Card Details")) {
                    TextField("Card ID", text: $cardID)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Card Name", text: $cardName)
                }
                Section {
                    Button("Add Card") {
                        let finalName = cardName.isEmpty ? "Card \(cardID.prefix(8))" : cardName
                        walletStore.addCard(AppleWalletCard(id: cardID, name: finalName))
                        dismiss()
                    }.disabled(cardID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Manual Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - ImportDefaultCardSheet
struct ImportDefaultCardSheet: View {
    @ObservedObject var walletStore: AppleWalletStore
    @Environment(\.dismiss) var dismiss

    @State private var cardID = ""
    @State private var cardName = ""
    @State private var showPicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Card Info")) {
                    TextField("Card ID", text: $cardID)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Card Name (optional)", text: $cardName)
                }
                Section(header: Text("ZIP File")) {
                    Button("Select ZIP") { showPicker = true }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    if isImporting { ProgressView("Importing...") }
                }
            }
            .navigationTitle("Import Default Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [UTType(filenameExtension: "zip") ?? .data, .data]
            ) { result in
                switch result {
                case .success(let url): Task { await importZIP(url) }
                case .failure(let err): errorMessage = err.localizedDescription
                }
            }
        }
    }

    private func importZIP(_ url: URL) async {
        let id = cardID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { errorMessage = "Card ID is required."; return }
        isImporting = true; errorMessage = nil
        defer { isImporting = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WalletImport_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        do {
            try FileManager.default.unzipItem(at: url, to: temp)
        } catch {
            errorMessage = "Unzip failed: \(error.localizedDescription)"; return
        }

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
        let root: URL
        if let folder = contents.first(where: {
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: temp.appendingPathComponent($0).path, isDirectory: &isDir)
            return isDir.boolValue
        }) {
            root = temp.appendingPathComponent(folder)
        } else {
            root = temp
        }

        let finalName = cardName.isEmpty ? "Card \(id.prefix(8))" : cardName
        var newCard = AppleWalletCard(id: id, name: finalName)
        var imported = 0

        if let d = try? Data(contentsOf: root.appendingPathComponent("FrontFace")) {
            newCard.frontFaceImageData = d; imported += 1
        }
        if let d = try? Data(contentsOf: root.appendingPathComponent("PlaceHolder")) {
            newCard.placeHolderImageData = d; imported += 1
        }
        if let d = try? Data(contentsOf: root.appendingPathComponent("Preview")) {
            newCard.previewImageData = d; imported += 1
        }
        if let d = try? Data(contentsOf: root.appendingPathComponent("cardBackgroundCombined@2x.png")) {
            newCard.useRetina = false; newCard.backgroundImageData = d; imported += 1
        }
        if let d = try? Data(contentsOf: root.appendingPathComponent("cardBackgroundCombined@3x.png")) {
            newCard.useRetina = true; newCard.backgroundImageData = d; imported += 1
        }
        if let d = try? Data(contentsOf: root.appendingPathComponent("pass.json")) {
            newCard.savePassJSON(d); imported += 1
        }

        guard imported > 0 else {
            errorMessage = "No known card files found in ZIP."; return
        }
        walletStore.addCard(newCard)
        dismiss()
    }
}

// MARK: - extractWalletCardID
func extractWalletCardID(from line: String) -> String? {
    if let m = regexMatch("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", line) {
        return m
    }
    if let m = regexMatch("(?:Card\\s*ID|Unique\\s*ID|SecureElementPass|DPAN)[^0-9A-Fa-f]{0,24}([0-9A-Fa-f]{8,})", line, group: 1) {
        return m
    }
    if let m = regexMatch("DPAN[:\\s]*([0-9]{8,})", line, group: 1) {
        return m
    }
    return nil
}

private func regexMatch(_ pattern: String, _ text: String, group: Int = 0) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let m = re.firstMatch(in: text, options: [], range: ns),
          let r = Range(m.range(at: group), in: text) else { return nil }
    return String(text[r])
}