import Foundation
import UIKit

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        let mgURL = URL(fileURLWithPath: onDeviceMGPath)
        let mgDir = mgURL.deletingLastPathComponent().path

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
        guard let inMemDict = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? NSDictionary,
              inMemDict["CacheExtra"] != nil || inMemDict["CacheData"] != nil else {
            throw mgError(-4, "Plist thiếu key bắt buộc — KHÔNG ghi.")
        }

        let fm = FileManager.default
        if !fm.isWritableFile(atPath: onDeviceMGPath) {
            onLogUpdate("[MG] Đang xin quyền ghi vào thư mục Caches...")
            let wq = WorseQuery()
            let res = wq.grantAccess(atPath: mgDir)
            if !res.0 {
                throw mgError(-5, "WorseQuery grant access thất bại: \(res.2)")
            }
            onLogUpdate("[MG] ✅ Đã được cấp quyền ghi.")
        }

        onLogUpdate("[MG] Đang ghi MobileGestalt.plist...")
        do {
            try plistData.write(to: mgURL)
        } catch {
            throw mgError(-6, "Ghi plist thất bại: \(error.localizedDescription)")
        }

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