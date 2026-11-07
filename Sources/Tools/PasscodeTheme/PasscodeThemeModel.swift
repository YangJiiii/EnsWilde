import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var passthm: UTType {
        UTType(importedAs: "com.enswilde.passthm")
    }
}

struct PasscodeTheme: Identifiable, Codable {
    let id: UUID
    var name: String
    var isSelected: Bool
    var customPrefix: PrefixLanguage
    var keySize: KeySize              // ← Stored, user chọn thủ công
    var telephonyVersion: TelephonyVersion
    var detectedSize: DetectedSize    // ← Chỉ để hiển thị info, không dùng để tính

    // MARK: - Enums

    enum BoldMode: String, Codable, CaseIterable {
        case regular = "Regular"
        case bold = "Bold"
        case both = "Regular + Bold"

        var displayName: String { rawValue }

        var suffixes: [String] {
            switch self {
            case .regular: return [""]
            case .bold: return ["-bold"]
            case .both: return ["", "-bold"]
            }
        }
    }

    enum PrefixLanguage: String, Codable, CaseIterable {
        case af = "af", ar = "ar", az = "az", bg = "bg", bn = "bn", ca = "ca", cs = "cs", da = "da", de = "de", el = "el", en = "en", es = "es", et = "et", eu = "eu", fa = "fa", fi = "fi", fil = "fil", fr = "fr", gl = "gl", he = "he", hi = "hi", hr = "hr", hu = "hu", hy = "hy", id = "id", `is` = "is", it = "it", ja = "ja", ka = "ka", kk = "kk", ko = "ko", lt = "lt", lv = "lv", mk = "mk", ml = "ml", mr = "mr", ms = "ms", nb = "nb", nl = "nl", nn = "nn", no = "no", pl = "pl", pt = "pt", ro = "ro", ru = "ru", sk = "sk", sl = "sl", sq = "sq", sr = "sr", sv = "sv", sw = "sw", ta = "ta", te = "te", th = "th", tr = "tr", uk = "uk", ur = "ur", vi = "vi", zh = "zh", other = "other"

        var displayName: String {
            switch self {
            case .af: return "Afrikaans"; case .ar: return "Arabic"; case .az: return "Azerbaijani"
            case .bg: return "Bulgarian"; case .bn: return "Bengali"; case .ca: return "Catalan"
            case .cs: return "Czech"; case .da: return "Danish"; case .de: return "German"
            case .el: return "Greek"; case .en: return "English"; case .es: return "Spanish"
            case .et: return "Estonian"; case .eu: return "Basque"; case .fa: return "Persian"
            case .fi: return "Finnish"; case .fil: return "Filipino"; case .fr: return "French"
            case .gl: return "Galician"; case .he: return "Hebrew"; case .hi: return "Hindi"
            case .hr: return "Croatian"; case .hu: return "Hungarian"; case .hy: return "Armenian"
            case .id: return "Indonesian"; case .`is`: return "Icelandic"; case .it: return "Italian"
            case .ja: return "Japanese"; case .ka: return "Georgian"; case .kk: return "Kazakh"
            case .ko: return "Korean"; case .lt: return "Lithuanian"; case .lv: return "Latvian"
            case .mk: return "Macedonian"; case .ml: return "Malayalam"; case .mr: return "Marathi"
            case .ms: return "Malay"; case .nb: return "Norwegian Bokmål"; case .nl: return "Dutch"
            case .nn: return "Norwegian Nynorsk"; case .no: return "Norwegian"; case .pl: return "Polish"
            case .pt: return "Portuguese"; case .ro: return "Romanian"; case .ru: return "Russian"
            case .sk: return "Slovak"; case .sl: return "Slovenian"; case .sq: return "Albanian"
            case .sr: return "Serbian"; case .sv: return "Swedish"; case .sw: return "Swahili"
            case .ta: return "Tamil"; case .te: return "Telugu"; case .th: return "Thai"
            case .tr: return "Turkish"; case .uk: return "Ukrainian"; case .ur: return "Urdu"
            case .vi: return "Vietnamese"; case .zh: return "Chinese"; case .other: return "Other"
            }
        }
    }

    enum KeySize: String, Codable, CaseIterable {
        case small = "Small Keys"
        case big = "Big Keys"

        static let smallTargetSize: CGFloat = 202.0
        static let bigTargetSize: CGFloat = 287.0
        static let resizeThreshold: CGFloat = 0.01
    }

    enum TelephonyVersion: String, Codable, CaseIterable {
        case telephony8 = "TelephonyUI-8", telephony9 = "TelephonyUI-9", telephony10 = "TelephonyUI-10"
        var displayName: String { rawValue }
        var cachePath: String { "/var/mobile/Library/Caches/\(self.rawValue)/" }
    }

    enum DetectedSize: Int, Codable {
        case unknown = 0, small = 1, big = 2
    }

    // MARK: - Computed

    var themeFolderURL: URL {
        URL.documentsDirectory
            .appendingPathComponent("PasscodeThemes")
            .appendingPathComponent(id.uuidString)
    }

    // MARK: - Init

    init(id: UUID = UUID(),
         name: String,
         customPrefix: PrefixLanguage = .en,
         keySize: KeySize = .small,
         telephonyVersion: TelephonyVersion = .telephony10,
         detectedSize: DetectedSize = .unknown) {
        self.id = id
        self.name = name
        self.isSelected = false
        self.customPrefix = customPrefix
        self.keySize = keySize
        self.telephonyVersion = telephonyVersion
        self.detectedSize = detectedSize
    }

    // MARK: - Custom Decodable (backward compat với file JSON cũ thiếu keySize)

    private enum CodingKeys: String, CodingKey {
        case id, name, isSelected, customPrefix, keySize, telephonyVersion, detectedSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self, forKey: .id)
        name             = try c.decode(String.self, forKey: .name)
        isSelected       = try c.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        customPrefix     = try c.decodeIfPresent(PrefixLanguage.self, forKey: .customPrefix) ?? .en
        keySize          = try c.decodeIfPresent(KeySize.self, forKey: .keySize) ?? .small
        telephonyVersion = try c.decodeIfPresent(TelephonyVersion.self, forKey: .telephonyVersion) ?? .telephony10
        detectedSize     = try c.decodeIfPresent(DetectedSize.self, forKey: .detectedSize) ?? .unknown
    }

    // MARK: - Helpers

    func getPreviewImage() -> UIImage? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: themeFolderURL.path) else { return nil }
        if let zeroFile = files.first(where: { $0.contains("-0-") || $0.contains("-0@") }) {
            return UIImage(contentsOfFile: themeFolderURL.appendingPathComponent(zeroFile).path)
        }
        return nil
    }

    func getImageFiles() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: themeFolderURL.path) else { return [] }
        return files.filter { file in
            let ext = (file as NSString).pathExtension.lowercased()
            return ext == "png" || ext == "jpg" || ext == "jpeg"
        }
    }
}

// MARK: - Store

class PasscodeThemeStore: ObservableObject {
    @Published var themes: [PasscodeTheme] = []
    @AppStorage("PasscodeThemeEnabled") var passcodeThemeEnabled: Bool = false
    @AppStorage("GlobalPasscodeLanguage") var globalCustomPrefixRaw: String = "en"
    @AppStorage("GlobalTelephonyVersion") var globalTelephonyVersionRaw: String = "TelephonyUI-10"
    @AppStorage("GlobalBoldMode") var globalBoldModeRaw: String = PasscodeTheme.BoldMode.regular.rawValue

    var globalCustomPrefix: PasscodeTheme.PrefixLanguage {
        get { PasscodeTheme.PrefixLanguage(rawValue: globalCustomPrefixRaw) ?? .en }
        set { globalCustomPrefixRaw = newValue.rawValue }
    }

    var globalTelephonyVersion: PasscodeTheme.TelephonyVersion {
        get { PasscodeTheme.TelephonyVersion(rawValue: globalTelephonyVersionRaw) ?? .telephony10 }
        set { globalTelephonyVersionRaw = newValue.rawValue }
    }

    var globalBoldMode: PasscodeTheme.BoldMode {
        get { PasscodeTheme.BoldMode(rawValue: globalBoldModeRaw) ?? .regular }
        set { globalBoldModeRaw = newValue.rawValue }
    }

    private let themesFileURL: URL

    init() {
        themesFileURL = URL.documentsDirectory.appendingPathComponent("PasscodeThemes.json")
        loadThemes()
    }

    func loadThemes() {
        guard FileManager.default.fileExists(atPath: themesFileURL.path) else { return }
        if let data = try? Data(contentsOf: themesFileURL),
           let decoded = try? JSONDecoder().decode([PasscodeTheme].self, from: data) {
            themes = decoded
        }
    }

    func saveThemes() {
        if let data = try? JSONEncoder().encode(themes) {
            try? data.write(to: themesFileURL, options: .atomic)
        }
    }

    func addTheme(_ theme: PasscodeTheme) { themes.append(theme); saveThemes() }
    func updateTheme(_ theme: PasscodeTheme) {
        if let idx = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[idx] = theme
            saveThemes()
        }
    }

    func deleteTheme(_ theme: PasscodeTheme) {
        themes.removeAll { $0.id == theme.id }
        saveThemes()
        try? FileManager.default.removeItem(at: theme.themeFolderURL)
    }

    func selectTheme(_ theme: PasscodeTheme) {
        for i in 0..<themes.count { themes[i].isSelected = false }
        if let idx = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[idx].isSelected = true
        }
        saveThemes()
    }

    func getSelectedTheme() -> PasscodeTheme? { themes.first { $0.isSelected } }
}