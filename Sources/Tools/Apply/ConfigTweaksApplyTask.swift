import Foundation

enum ConfigTweaksApplyTask {
    static let footnotePath = "/var/mobile/Library/Preferences/com.apple.lockscreen.shared.plist"
    static let footnoteKey  = "SBLockScreenFootnoteText"

    static let supervisionPath   = "/var/mobile/Library/Preferences/com.apple.mobileactivationd.plist"
    static let supervisionKey    = "IsSupervised"
    static let supervisorHostKey = "SupervisorHostName"

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
            try setString(path: footnotePath, key: footnoteKey, value: nil)
        } else {
            onLogUpdate("[Footnote] Ghi \"\(footnoteText)\"...")
            try setString(path: footnotePath, key: footnoteKey, value: footnoteText)
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
            onLogUpdate("[Supervision] Tắt supervision.")
            let dict = loadPlist(at: supervisionPath)
            if dict[supervisionKey] != nil || dict[supervisorHostKey] != nil {
                dict.removeObject(forKey: supervisionKey)
                dict.removeObject(forKey: supervisorHostKey)
                try writePlist(dict, to: supervisionPath)
            }
            onLogUpdate("[Supervision] ✅ Tắt xong.")
        }

        onLogUpdate("[Config] ✅ Config Tweaks đã apply. Respring để thay đổi có hiệu lực.")
    }

    // MARK: - Plist I/O

    private static func loadPlist(at path: String) -> NSMutableDictionary {
        guard FileManager.default.fileExists(atPath: path) else {
            return NSMutableDictionary()
        }
        return NSMutableDictionary(contentsOfFile: path) ?? NSMutableDictionary()
    }

    private static func writePlist(_ dict: NSMutableDictionary, to path: String) throws {
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        } catch {
            throw cfgError(-20, "Serialize plist thất bại: \(error.localizedDescription)")
        }
        guard (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil else {
            throw cfgError(-21, "Verify in-memory thất bại, không ghi.")
        }

        let bq = BadQuery()
        let dir = (path as NSString).deletingLastPathComponent

        // FIX: Xin quyền cho thư mục cha trước (Preferences), nếu fail mới xin cho file
        var granted = bq.grantAccess(atPath: dir).0
        if !granted {
            granted = bq.grantAccess(atPath: path).0
        }

        if granted {
            // Ghi trực tiếp bằng FileManager sau khi đã grant quyền
            if !dict.write(toFile: path, atomically: true) {
                throw cfgError(-22, "FileManager không ghi được file: \(path)")
            }
        } else {
            // Fallback: Dùng BadQueryWrapper (đề phòng trường hợp BadQueryWrapper xử lý khác)
            do {
                try BadQueryWrapper.writeFile(at: path, data: data)
            } catch {
                throw cfgError(-23, "Ghi thất bại tại \(path) (BadQuery grant fail): \(error.localizedDescription)")
            }
        }

        // Verify từ đĩa
        if let written = try? Data(contentsOf: URL(fileURLWithPath: path)),
           (try? PropertyListSerialization.propertyList(from: written, format: nil)) == nil {
            throw cfgError(-24, "File sau khi ghi không parse được: \(path)")
        }
    }

    private static func setString(path: String, key: String, value: String?) throws {
        if !FileManager.default.fileExists(atPath: path) && value == nil { return }
        let dict = loadPlist(at: path)
        if let value = value {
            dict[key] = value
        } else {
            guard dict[key] != nil else { return }
            dict.removeObject(forKey: key)
        }
        try writePlist(dict, to: path)
    }

    private static func cfgError(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "ConfigTweak", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}