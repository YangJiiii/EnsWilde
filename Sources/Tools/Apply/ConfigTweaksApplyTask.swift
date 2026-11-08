import Foundation

enum ConfigTweaksApplyTask {
    // Đường dẫn chuẩn theo Erosion
    static let configDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static let footnoteURL = URL(fileURLWithPath: configDir).appendingPathComponent("SharedDeviceConfiguration.plist")
    static let supervisionURL = URL(fileURLWithPath: configDir).appendingPathComponent("CloudConfigurationDetails.plist")

    static func apply(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let footnoteText = UserDefaults.standard.string(forKey: "ConfigFootnoteText") ?? ""
        let isSupervised = UserDefaults.standard.bool(forKey: "ConfigSupervised")
        let orgName = UserDefaults.standard.string(forKey: "ConfigOrgName") ?? "EnsWilde"

        if footnoteText.isEmpty && !isSupervised {
            onLogUpdate("[Config] Không có thay đổi nào để ghi.")
            return
        }

        let wq = WorseQuery()
        let fm = FileManager.default

        // Xin quyền cho thư mục cha
        if !fm.isWritableFile(atPath: footnoteURL.path) || !fm.isWritableFile(atPath: supervisionURL.path) {
            onLogUpdate("[Config] Đang xin quyền ghi vào ConfigurationProfiles...")
            let res = wq.grantAccess(atPath: configDir)
            if !res.0 {
                throw NSError(domain: "ConfigTweak", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "WorseQuery grant access thất bại: \(res.2)"
                ])
            }
            onLogUpdate("[Config] ✅ Đã được cấp quyền ghi.")
        }

        // 1. Xử lý Footnote
        if footnoteText.isEmpty {
            onLogUpdate("[Footnote] Không có text — xoá key nếu tồn tại.")
            try setString(url: footnoteURL, key: "LockScreenFootnote", value: nil)
        } else {
            onLogUpdate("[Footnote] Ghi \"\(footnoteText)\"...")
            try setString(url: footnoteURL, key: "LockScreenFootnote", value: footnoteText)
            onLogUpdate("[Footnote] ✅ Xong.")
        }

        // 2. Xử lý Supervision
        if isSupervised {
            onLogUpdate("[Supervision] Bật supervision...")
            var dict = loadPlist(url: supervisionURL)
            dict["IsSupervised"] = true
            dict["OrganizationName"] = orgName
            try writePlist(dict, to: supervisionURL)
            onLogUpdate("[Supervision] ✅ Bật xong.")
        } else {
            onLogUpdate("[Supervision] Tắt supervision.")
            var dict = loadPlist(url: supervisionURL)
            if dict["IsSupervised"] != nil || dict["OrganizationName"] != nil {
                dict.removeObject(forKey: "IsSupervised")
                dict.removeObject(forKey: "OrganizationName")
                try writePlist(dict, to: supervisionURL)
            }
            onLogUpdate("[Supervision] ✅ Tắt xong.")
        }

        onLogUpdate("[Config] ✅ Config Tweaks đã apply. Respring để thay đổi có hiệu lực.")
    }

    private static func loadPlist(url: URL) -> NSMutableDictionary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return NSMutableDictionary()
        }
        return NSMutableDictionary(contentsOf: url) ?? NSMutableDictionary()
    }

    private static func writePlist(_ dict: NSMutableDictionary, to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try data.write(to: url)
    }

    private static func setString(url: URL, key: String, value: String?) throws {
        var dict = loadPlist(url: url)
        if let value = value {
            dict[key] = value
        } else {
            guard dict[key] != nil else { return }
            dict.removeObject(forKey: key)
        }
        try writePlist(dict, to: url)
    }
}