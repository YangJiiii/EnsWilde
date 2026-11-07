import Foundation
import UIKit

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    // MARK: - Public API

    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        let mgPath = onDeviceMGPath
        let mgURL  = URL(fileURLWithPath: mgPath)

        // ── L1: Sanity ─────────────────────────────────────────────
        guard !store.mgCurrentDict.isEmpty else {
            throw mgError(-1, "Store rỗng. Vào tab MobileGestalt, chỉnh vài thứ rồi Save Settings trước khi Apply.")
        }
        guard FileManager.default.fileExists(atPath: mgPath) else {
            throw mgError(-2, "Không tìm thấy MobileGestalt.plist tại \(mgPath). Không ghi.")
        }

        // ── L2: Backup pristine (BẮT BUỘC trước khi ghi lần đầu) ──
        if !MobileGestaltBackupManager.shared.hasBackup {
            onLogUpdate("[MG] Lần đầu apply — tạo backup pristine...")
            let originalData: Data
            do {
                originalData = try Data(contentsOf: mgURL)
            } catch {
                throw mgError(-3, "Không đọc được file gốc để backup: \(error.localizedDescription)")
            }
            // Verify pristine parse được TRƯỚC khi lưu làm backup
            guard (try? PropertyListSerialization.propertyList(from: originalData, format: nil)) != nil else {
                throw mgError(-4, "File gốc không parse được — dừng ngay để tránh bootloop.")
            }
            try MobileGestaltBackupManager.shared.ensureBackup(from: originalData)
            guard MobileGestaltBackupManager.shared.hasBackup else {
                throw mgError(-5, "Backup không được tạo thành công — dừng.")
            }
            onLogUpdate("[MG] ✅ Đã backup pristine.")
        } else {
            onLogUpdate("[MG] Đã có backup pristine từ trước.")
        }

        // ── L3: Serialize + verify in-memory ──────────────────────
        onLogUpdate("[MG] Đang serialize plist...")
        let plistData: Data
        do {
            plistData = try PropertyListSerialization.data(
                fromPropertyList: store.mgCurrentDict, format: .binary, options: 0
            )
        } catch {
            throw mgError(-6, "Serialize plist thất bại: \(error.localizedDescription)")
        }

        onLogUpdate("[MG] Verify cấu trúc plist trước khi ghi...")
        guard let inMemDict = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? NSDictionary else {
            throw mgError(-7, "Parse in-memory thất bại — KHÔNG ghi file.")
        }
        guard inMemDict["CacheExtra"] != nil || inMemDict["CacheData"] != nil else {
            throw mgError(-8, "Plist thiếu cả CacheExtra và CacheData — KHÔNG ghi file.")
        }

        // ── L4: Ghi atomic qua BadQueryWrapper ────────────────────
        onLogUpdate("[MG] Đang ghi qua BadQuery (atomic)...")
        do {
            try BadQueryWrapper.writeFile(at: mgPath, data: plistData)
        } catch {
            // Atomic write fail → file gốc vẫn nguyên vẹn, KHÔNG cần rollback
            let hint: String
            if let bqErr = error as? BadQueryError {
                switch bqErr {
                case .kernelDenied:
                    hint = "BadQuery bị iOS patch trên thiết bị này → không thể ghi qua sandbox."
                case .outsideSandbox:
                    hint = "Path ngoài sandbox → BadQuery không grant được."
                case .cantResolve:
                    hint = "Không tìm thấy symbol bad_query trong binary → libairlift không hỗ trợ."
                default:
                    hint = ""
                }
            } else {
                hint = ""
            }
            throw mgError(-9, "Ghi plist thất bại: \(error.localizedDescription)\(hint.isEmpty ? "" : " — \(hint)")")
        }

        // ── L5: Verify từ đĩa ─────────────────────────────────────
        onLogUpdate("[MG] Verify file sau khi ghi...")
        do {
            let writtenData = try Data(contentsOf: mgURL)
            guard let writtenDict = try PropertyListSerialization.propertyList(from: writtenData, format: nil) as? NSDictionary else {
                throw mgError(-10, "File sau khi ghi không parse được.")
            }
            guard writtenDict["CacheExtra"] != nil || writtenDict["CacheData"] != nil else {
                throw mgError(-11, "File sau khi ghi thiếu key bắt buộc.")
            }
        } catch {
            onLogUpdate("[MG] ⚠️ Verify thất bại — rollback về pristine...")
            try? rollbackFromBackup()
            throw mgError(-12, "File sau khi ghi corrupt, đã rollback: \(error.localizedDescription)")
        }

        onLogUpdate("[MG] ✅ MobileGestalt đã apply thành công. Respring để thay đổi có hiệu lực.")
    }

    // MARK: - Rollback

    private static func rollbackFromBackup() throws {
        let pristineData = try MobileGestaltBackupManager.shared.restoreData()
        try BadQueryWrapper.writeFile(at: onDeviceMGPath, data: pristineData)
    }

    // MARK: - Error helper

    private static func mgError(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "MobileGestalt", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}