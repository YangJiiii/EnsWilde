import Foundation
import UIKit
import AirliftFFI
import Darwin
import Security
import XPC

// Native WorseQuery & typealias được khai báo duy nhất trong SettingsView.swift
// SecTaskCreateFromSelf / SecTaskCopyValueForEntitlement đã có @_silgen_name ở SettingsView.swift

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        let mgURL = URL(fileURLWithPath: onDeviceMGPath)

        guard store.mgCurrentDict.count > 0 else {
            throw mgError(-1, "Store rỗng. Chỉnh gì đó rồi Save Settings trước khi Apply.")
        }
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw mgError(-2, "Không tìm thấy MobileGestalt.plist.")
        }

        if !MobileGestaltBackupManager.shared.hasBackup {
            onLogUpdate("[MG] Đang backup pristine...")
            let originalData = try Data(contentsOf: mgURL)
            guard (try? PropertyListSerialization.propertyList(from: originalData, format: nil)) != nil else {
                throw mgError(-3, "File gốc không parse được — dừng để tránh bootloop.")
            }
            try MobileGestaltBackupManager.shared.ensureBackup(from: originalData)
            onLogUpdate("[MG] ✅ Đã backup pristine.")
        }

        onLogUpdate("[MG] Đang serialize plist...")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: store.mgCurrentDict, format: .binary, options: 0
        )

        onLogUpdate("[MG] Đang xin quyền ghi (Native WorseQuery)...")
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            throw mgError(-5, "Không tìm thấy App Group!")
        }

        // Signature canonical: grantAccess(targetPath:appGroupID:) -> (Int64, String)
        // targetPath = thư mục Caches của MobileGestalt (symlink target) — giống SettingsView
        let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let (handle, accessMsg) = NativeWorseQuery.shared.grantAccess(targetPath: targetDir, appGroupID: group)
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại: \(accessMsg). Hãy chắc chắn cert có App Group hợp lệ.")
        }
        onLogUpdate("[MG] ✅ Đã được cấp quyền ghi.")

        defer { NativeWorseQuery.shared.releaseAll() }

        // Gỡ cờ immutable
        var st = stat()
        if stat(onDeviceMGPath, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
            _ = chflags(onDeviceMGPath, st.st_flags & ~UInt32(UF_IMMUTABLE))
        }

        onLogUpdate("[MG] Đang ghi đè MobileGestalt.plist (In-place)...")
        let fd = open(onDeviceMGPath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw mgError(-6, "Mở file thất bại (errno: \(errno))")
        }
        defer { close(fd) }

        let bytesWritten = plistData.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
        guard bytesWritten == plistData.count else {
            throw mgError(-6, "Ghi file thất bại (errno: \(errno))")
        }

        _ = fcntl(fd, F_FULLFSYNC)

        onLogUpdate("[MG] Verify file sau khi ghi...")
        do {
            let writtenData = try Data(contentsOf: mgURL)
            guard let writtenDict = try PropertyListSerialization.propertyList(from: writtenData, format: nil) as? NSDictionary,
                  writtenDict["CacheExtra"] != nil || writtenDict["CacheData"] != nil else {
                throw mgError(-7, "File sau khi ghi không hợp lệ.")
            }
        } catch {
            onLogUpdate("[MG] ⚠️ Verify thất bại — rollback...")
            let pristineData = try MobileGestaltBackupManager.shared.restoreData()
            try? pristineData.write(to: mgURL)
            throw mgError(-8, "File sau khi ghi corrupt, đã rollback: \(error.localizedDescription)")
        }

        onLogUpdate("[MG] ✅ MobileGestalt đã apply thành công. Respring để thay đổi.")
    }

    private static func mgError(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "MobileGestalt", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}