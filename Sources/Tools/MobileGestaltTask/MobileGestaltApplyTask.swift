import Foundation
import UIKit

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        let mgPath = onDeviceMGPath
        let mgURL = URL(fileURLWithPath: mgPath)

        // ── 1) File phải tồn tại ────────────────────────────────────
        guard FileManager.default.fileExists(atPath: mgPath) else {
            throw NSError(domain: "MG", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Không tìm thấy MobileGestalt.plist tại \(mgPath). Không ghi gì cả."
            ])
        }

        // ── 2) Backup pristine (chỉ 1 lần) ─────────────────────────
        onLogUpdate("[MG] Đang backup MobileGestalt gốc...")
        if let currentData = try? Data(contentsOf: mgURL) {
            try? MobileGestaltBackupManager.shared.ensureBackup(from: currentData)
        }
        guard MobileGestaltBackupManager.shared.hasBackup else {
            throw NSError(domain: "MG", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Không tạo được backup pristine. Dừng để tránh bootloop."
            ])
        }

        // ── 3) Serialize + verify in-memory ────────────────────────
        onLogUpdate("[MG] Đang serialize plist...")
        let plistData: Data
        do {
            plistData = try PropertyListSerialization.data(
                fromPropertyList: store.mgCurrentDict, format: .binary, options: 0
            )
        } catch {
            throw NSError(domain: "MG", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Serialize plist thất bại: \(error.localizedDescription)"
            ])
        }

        onLogUpdate("[MG] Verify cấu trúc plist trước khi ghi...")
        do {
            guard let dict = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? NSDictionary else {
                throw NSError(domain: "MG", code: -4, userInfo: [NSLocalizedDescriptionKey: "Parse không ra dict"])
            }
            // Plist hợp lệ PHẢI có ít nhất 1 trong 2 key bắt buộc
            guard dict["CacheExtra"] != nil || dict["CacheData"] != nil else {
                throw NSError(domain: "MG", code: -5, userInfo: [NSLocalizedDescriptionKey: "Thiếu cả CacheExtra và CacheData"])
            }
        } catch {
            // Verify fail → KHÔNG ghi, không cần rollback vì chưa đụng file
            throw NSError(domain: "MG", code: -6, userInfo: [
                NSLocalizedDescriptionKey: "Verify in-memory thất bại, KHÔNG ghi file (tránh bootloop): \(error.localizedDescription)"
            ])
        }

        // ── 4) Ghi qua BadQueryWrapper (atomic) ────────────────────
        onLogUpdate("[MG] Đang ghi qua BadQuery...")
        do {
            try BadQueryWrapper.writeFile(at: mgPath, data: plistData)
        } catch {
            onLogUpdate("[MG] ⚠️ Ghi thất bại: \(error.localizedDescription). Đang rollback...")
            try? rollbackFromBackup()
            throw NSError(domain: "MG", code: -7, userInfo: [
                NSLocalizedDescriptionKey: "Ghi plist thất bại, đã rollback: \(error.localizedDescription)"
            ])
        }

        // ── 5) Verify từ đĩa ──────────────────────────────────────
        onLogUpdate("[MG] Verify file sau khi ghi...")
        do {
            let writtenData = try Data(contentsOf: mgURL)
            guard let writtenDict = try PropertyListSerialization.propertyList(from: writtenData, format: nil) as? NSDictionary else {
                throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: "Parse file sau khi ghi thất bại"])
            }
            guard writtenDict["CacheExtra"] != nil || writtenDict["CacheData"] != nil else {
                throw NSError(domain: "MG", code: -9, userInfo: [NSLocalizedDescriptionKey: "File sau khi ghi thiếu key bắt buộc"])
            }
        } catch {
            onLogUpdate("[MG] ⚠️ File sau khi ghi bị corrupt. Rollback...")
            try? rollbackFromBackup()
            throw NSError(domain: "MG", code: -10, userInfo: [
                NSLocalizedDescriptionKey: "File sau khi ghi corrupt, đã rollback: \(error.localizedDescription)"
            ])
        }

        onLogUpdate("[MG] ✅ MobileGestalt đã apply. Respring để thay đổi có hiệu lực.")
    }

    /// Rollback: đọc pristine backup → ghi ngược lại device
    private static func rollbackFromBackup() throws {
        let pristineData = try MobileGestaltBackupManager.shared.restoreData()
        try BadQueryWrapper.writeFile(at: onDeviceMGPath, data: pristineData)
    }
}