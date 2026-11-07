import Foundation

enum ConfigTweaksApplyTask {
    static let footnotePath = "/var/mobile/Library/Preferences/com.apple.lockscreen.shared.plist"
    static let footnoteKey  = "SBLockScreenFootnoteText"

    static let supervisionPath   = "/var/mobile/Library/Preferences/com.apple.mobileactivationd.plist"
    static let supervisionKey    = "IsSupervised"
    static let supervisorHostKey = "SupervisorHostName"

    static func apply(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        // Đọc state trực tiếp từ UserDefaults (AppStorage trong ConfigView)
        let footnoteText = UserDefaults.standard.string(forKey: "ConfigFootnoteText") ?? ""
        let isSupervised = UserDefaults.standard.bool(forKey: "ConfigSupervised")

        if footnoteText.isEmpty && !isSupervised {
            onLogUpdate("[Config] Không có thay đổi nào cần ghi (footnote trống + supervision tắt).")
            return
        }

        // ── 1. FOOTNOTE ────────────────────────────────────────────
        if footnoteText.isEmpty {
            onLogUpdate("[Footnote] Không có text → xoá key (nếu tồn tại).")
            try updatePlistString(path: footnotePath, key: footnoteKey, value: nil)
        } else {
            onLogUpdate("[Footnote] Ghi \"\(footnoteText)\"...")
            try updatePlistString(path: footnotePath, key: footnoteKey, value: footnoteText)
            onLogUpdate("[Footnote] ✅ Xong.")
        }

        // ── 2. SUPERVISION ─────────────────────────────────────────
        if isSupervised {
            onLogUpdate("[Supervision] Bật supervision...")
            let dict = loadPlist(at: supervisionPath)
            dict[supervisionKey]    = true
            dict[supervisorHostKey] = "EnsWilde"
            try writePlist(dict, to: supervisionPath)
            onLogUpdate("[Supervision] ✅ Bật xong.")
        } else {
            onLogUpdate("[Supervision] Tắt supervision (xoá key nếu tồn tại).")
            let dict = loadPlist(at: supervisionPath)
            if dict[supervisionKey] != nil || dict[supervisorHostKey] != nil {
                dict.removeObject(forKey: supervisionKey)
                dict.removeObject(forKey: supervisorHostKey)
                try writePlist(dict, to: supervisionPath)
            }
            onLogUpdate("[Supervision] ✅ Tắt xong.")
        }

        onLogUpdate("[Config] ✅ Config Tweak đã apply. Respring để thay đổi có hiệu lực.")
    }

    // MARK: - Helpers

    private static func loadPlist(at path: String) -> NSMutableDictionary {
        guard FileManager.default.fileExists(atPath: path) else {
            return NSMutableDictionary()
        }
        if let dict = NSMutableDictionary(contentsOfFile: path) {
            return dict
        }
        // File tồn tại nhưng parse fail → KHÔNG ghi đè để tránh corrupt thêm
        return NSMutableDictionary()
    }

    private static func writePlist(_ dict: NSMutableDictionary, to path: String) throws {
        // Serialize binary plist (iOS gốc dùng binary, không dùng XML)
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        } catch {
            throw NSError(domain: "ConfigTweak", code: -20, userInfo: [
                NSLocalizedDescriptionKey: "Serialize plist thất bại: \(error.localizedDescription)"
            ])
        }

        // Verify in-memory trước khi ghi
        guard (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil else {
            throw NSError(domain: "ConfigTweak", code: -21, userInfo: [
                NSLocalizedDescriptionKey: "Verify in-memory thất bại, không ghi file."
            ])
        }

        // Ghi qua BadQueryWrapper (atomic)
        do {
            try BadQueryWrapper.writeFile(at: path, data: data)
        } catch {
            throw NSError(domain: "ConfigTweak", code: -22, userInfo: [
                NSLocalizedDescriptionKey: "Ghi plist thất bại tại \(path): \(error.localizedDescription)"
            ])
        }

        // Verify từ đĩa
        if let writtenData = try? Data(contentsOf: URL(fileURLWithPath: path)),
           (try? PropertyListSerialization.propertyList(from: writtenData, format: nil)) == nil {
            throw NSError(domain: "ConfigTweak", code: -23, userInfo: [
                NSLocalizedDescriptionKey: "File sau khi ghi không parse được: \(path)"
            ])
        }
    }

    private static func updatePlistString(path: String, key: String, value: String?) throws {
        // Nếu file không tồn tại và không có gì để ghi → bỏ qua
        if !FileManager.default.fileExists(atPath: path) && value == nil { return }

        var dict = loadPlist(at: path)
        if let value = value {
            dict[key] = value
        } else {
            guard dict[key] != nil else { return }
            dict.removeObject(forKey: key)
        }
        try writePlist(dict, to: path)
    }
}
