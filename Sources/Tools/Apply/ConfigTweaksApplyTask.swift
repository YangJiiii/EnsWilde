import Foundation
import Darwin
import Security

// SecTaskCreateFromSelf & SecTaskCopyValueForEntitlement đã được khai báo
// (internal) trong Sources/UI/SettingsView.swift → dùng chung trong module.
// KHÔNG khai báo lại ở đây để tránh lỗi "invalid redeclaration".

enum ConfigTweaksApplyTask {
    // Đường dẫn chuẩn
    static let configDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static let footnoteURL = URL(fileURLWithPath: configDir).appendingPathComponent("SharedDeviceConfiguration.plist")
    static let supervisionURL = URL(fileURLWithPath: configDir).appendingPathComponent("CloudConfigurationDetails.plist")

    static func apply(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let footnoteText = UserDefaults.standard.string(forKey: "ConfigFootnoteText") ?? ""
        let isSupervised = UserDefaults.standard.bool(forKey: "ConfigSupervised")
        let orgName = UserDefaults.standard.string(forKey: "ConfigOrgName") ?? "EnsWilde"

        // 🔥 ĐÃ FIX: Bỏ đoạn early-return để app có thể xoá key khi Restore
        // if footnoteText.isEmpty && !isSupervised {
        //     onLogUpdate("[Config] Không có thay đổi nào để ghi.")
        //     return
        // }

        let fm = FileManager.default

        // 1. Lấy App Group
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            throw NSError(domain: "ConfigTweak", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Không tìm thấy App Group!"
            ])
        }

        // 2. Xin quyền ghi bằng NativeWorseQuery (MCM Symlink)
        onLogUpdate("[Config] Đang xin quyền ghi vào ConfigurationProfiles...")
        let (handle, errorMsg) = NativeWorseQuery.shared.grantAccess(targetPath: configDir, appGroupID: group)

        guard handle > 0 else {
            throw NSError(domain: "ConfigTweak", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Xin quyền thất bại: \(errorMsg)"
            ])
        }
        onLogUpdate("[Config] ✅ Đã được cấp quyền ghi.")
        defer { NativeWorseQuery.shared.releaseAll() }

        // 3. Xử lý Footnote
        if footnoteText.isEmpty {
            onLogUpdate("[Footnote] Không có text — xoá key nếu tồn tại.")
            try setString(url: footnoteURL, key: "LockScreenFootnote", value: nil)
        } else {
            onLogUpdate("[Footnote] Ghi \"\(footnoteText)\"...")
            try setString(url: footnoteURL, key: "LockScreenFootnote", value: footnoteText)
            onLogUpdate("[Footnote] ✅ Xong.")
        }

        // 4. Xử lý Supervision
        if isSupervised {
            onLogUpdate("[Supervision] Bật supervision...")
            let dict = loadPlist(url: supervisionURL)
            dict["IsSupervised"] = true
            dict["OrganizationName"] = orgName
            try writePlist(dict, to: supervisionURL)
            onLogUpdate("[Supervision] ✅ Bật xong.")
        } else {
            onLogUpdate("[Supervision] Tắt supervision.")
            let dict = loadPlist(url: supervisionURL)
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
        try writeFileInPlace(url: url, data: data)
    }

    private static func setString(url: URL, key: String, value: String?) throws {
        let dict = loadPlist(url: url)
        if let value = value {
            dict[key] = value
        } else {
            guard dict[key] != nil else { return }
            dict.removeObject(forKey: key)
        }
        try writePlist(dict, to: url)
    }

    /// Ghi đè file an toàn: pwrite từ offset 0, ftruncate cắt phần dư, F_FULLFSYNC đồng bộ.
    private static func writeFileInPlace(url: URL, data: Data) throws {
        let path = url.path

        // Gỡ cờ immutable nếu có
        var st = stat()
        if stat(path, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
            _ = chflags(path, st.st_flags & ~UInt32(UF_IMMUTABLE))
        }

        // Mở file, nếu chưa có thì tạo mới (O_CREAT)
        let fd = open(path, O_RDWR | O_CLOEXEC | O_CREAT, 0644)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Mở file thất bại: \(url.lastPathComponent) (errno: \(errno))"
            ])
        }
        defer { close(fd) }

        // Ghi đè từ đầu
        let written = data.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
        guard written == data.count else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Ghi file thất bại: \(url.lastPathComponent) (errno: \(errno))"
            ])
        }

        // Cắt phần dư của file cũ
        if ftruncate(fd, off_t(data.count)) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "ftruncate thất bại: \(url.lastPathComponent) (errno: \(errno))"
            ])
        }

        // Đồng bộ xuống đĩa
        _ = fcntl(fd, F_FULLFSYNC)
    }
}