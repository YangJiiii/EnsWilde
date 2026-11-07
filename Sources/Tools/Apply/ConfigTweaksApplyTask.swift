import Foundation

enum ConfigTweaksApplyTask {
    // Đường dẫn gốc không thể ghi trực tiếp bằng bad_query
    static let footnotePath = "/var/mobile/Library/Preferences/com.apple.lockscreen.shared.plist"
    static let footnoteKey  = "SBLockScreenFootnoteText"

    static let supervisionPath   = "/var/mobile/Library/Preferences/com.apple.mobileactivationd.plist"
    static let supervisionKey    = "IsSupervised"
    static let supervisorHostKey = "SupervisorHostName"

    // Đường dẫn tạm nằm trong sandbox của app (được phép ghi)
    static var tempFootnoteURL: URL {
        URL.documentsDirectory.appendingPathComponent("com.apple.lockscreen.shared.plist")
    }
    static var tempSupervisionURL: URL {
        URL.documentsDirectory.appendingPathComponent("com.apple.mobileactivationd.plist")
    }

    static func apply(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let footnoteText = UserDefaults.standard.string(forKey: "ConfigFootnoteText") ?? ""
        let isSupervised = UserDefaults.standard.bool(forKey: "ConfigSupervised")

        if footnoteText.isEmpty && !isSupervised {
            onLogUpdate("[Config] Không có thay đổi nào để ghi (footnote trống + supervision tắt).")
            return
        }

        // ── 1. FOOTNOTE ────────────────────────────────────────────
        if footnoteText.isEmpty {
            onLogUpdate("[Footnote] Không có text — xoá key nếu tồn tại.")
            try setString(path: footnotePath, tempURL: tempFootnoteURL, key: footnoteKey, value: nil)
        } else {
            onLogUpdate("[Footnote] Ghi \"\(footnoteText)\"...")
            try setString(path: footnotePath, tempURL: tempFootnoteURL, key: footnoteKey, value: footnoteText)
            onLogUpdate("[Footnote] ✅ Xong.")
        }

        // ── 2. SUPERVISION ─────────────────────────────────────────
        if isSupervised {
            onLogUpdate("[Supervision] Bật supervision...")
            var dict = loadPlist(at: tempSupervisionURL)
            dict[supervisionKey]    = true
            dict[supervisorHostKey] = "EnsWilde"
            try writePlist(dict, to: supervisionPath, tempURL: tempSupervisionURL)
            onLogUpdate("[Supervision] ✅ Bật xong.")
        } else {
            onLogUpdate("[Supervision] Tắt supervision.")
            var dict = loadPlist(at: tempSupervisionURL)
            if dict[supervisionKey] != nil || dict[supervisorHostKey] != nil {
                dict.removeObject(forKey: supervisionKey)
                dict.removeObject(forKey: supervisorHostKey)
                try writePlist(dict, to: supervisionPath, tempURL: tempSupervisionURL)
            }
            onLogUpdate("[Supervision] ✅ Tắt xong.")
        }

        onLogUpdate("[Config] ✅ Config Tweaks đã apply. Respring để thay đổi có hiệu lực.")
    }

    // MARK: - Helpers

    private static func loadPlist(at tempURL: URL) -> NSMutableDictionary {
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            return NSMutableDictionary()
        }
        return NSMutableDictionary(contentsOf: tempURL) ?? NSMutableDictionary()
    }

    private static func writePlist(_ dict: NSMutableDictionary, to path: String, tempURL: URL) throws {
        // 1. Ghi file tạm trong Documents
        if !dict.write(to: tempURL, atomically: true) {
            throw cfgError(-20, "Không thể tạo file tạm tại \(tempURL.path)")
        }

        // 2. Đọc dữ liệu từ file tạm
        let data = try Data(contentsOf: tempURL)

        // 3. Dùng BadQueryWrapper để ghi ra đường dẫn đích
        do {
            try BadQueryWrapper.writeFile(at: path, data: data)
        } catch {
            throw cfgError(-21, "Ghi thất bại tại \(path) (BadQuery grant fail): \(error.localizedDescription)")
        }

        // 4. Dọn dẹp file tạm
        try? FileManager.default.removeItem(at: tempURL)
    }

    private static func setString(path: String, tempURL: URL, key: String, value: String?) throws {
        var dict = loadPlist(at: tempURL)
        if let value = value {
            dict[key] = value
        } else {
            guard dict[key] != nil else { return }
            dict.removeObject(forKey: key)
        }
        try writePlist(dict, to: path, tempURL: tempURL)
    }

    private static func cfgError(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "ConfigTweak", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}