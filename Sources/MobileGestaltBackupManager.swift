import Foundation
import CryptoKit

final class MobileGestaltBackupManager {
    static let shared = MobileGestaltBackupManager()

    struct BackupInfo {
        let createdAt: Date
        let byteCount: Int
    }

    struct BackupRecord {
        let id: UUID
        let url: URL
        let sha256: String
        let byteCount: Int
        let date: Date
    }

    private let fm = FileManager.default
    private var backupDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnsWilde/Backups", isDirectory: true)
    }

    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func createBackup(from data: Data, reason: String = "Before applying") throws -> BackupRecord {
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let id = UUID()
        let url = backupDir.appendingPathComponent("\(id.uuidString).plist")
        try data.write(to: url, options: .atomic)
        
        let hash = Self.sha256(data)
        let meta = ["id": id.uuidString, "sha256": hash, "byteCount": "\(data.count)", "reason": reason]
        let metaURL = backupDir.appendingPathComponent("\(id.uuidString).json")
        try JSONSerialization.data(withJSONObject: meta).write(to: metaURL)
        
        return BackupRecord(id: id, url: url, sha256: hash, byteCount: data.count, date: Date())
    }

    func backupData(_ record: BackupRecord) throws -> Data {
        let data = try Data(contentsOf: record.url)
        guard data.count == record.byteCount, Self.sha256(data) == record.sha256 else {
            throw NSError(domain: "Backup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Backup bị hỏng (SHA256 không khớp)."])
        }
        return data
    }

    func latestBackup() -> BackupRecord? {
        guard let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return nil }
        let plists = files.filter { $0.pathExtension == "plist" }
        guard let latest = plists.max(by: { url1, url2 in
            let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return d1 < d2
        }) else { return nil }
        
        guard let id = UUID(uuidString: latest.deletingPathExtension().lastPathComponent),
              let metaData = try? Data(contentsOf: backupDir.appendingPathComponent("\(id.uuidString).json")),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: String],
              let hash = meta["sha256"], let countStr = meta["byteCount"], let count = Int(countStr) else { return nil }
        
        return BackupRecord(id: id, url: latest, sha256: hash, byteCount: count, date: Date())
    }

    var hasBackup: Bool {
        return latestBackup() != nil
    }

    var info: BackupInfo? {
        guard let record = latestBackup() else { return nil }
        let createdAt = (try? record.url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? record.date
        return BackupInfo(createdAt: createdAt, byteCount: record.byteCount)
    }

    func importBackup(from data: Data) throws {
        _ = try createBackup(from: data, reason: "Imported")
    }

    @discardableResult
    func ensureBackup(from data: Data) throws -> BackupInfo {
        let newHash = Self.sha256(data)
        if let existing = latestBackup(), existing.sha256 == newHash {
            let createdAt = (try? existing.url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? existing.date
            return BackupInfo(createdAt: createdAt, byteCount: existing.byteCount)
        }
        let record = try createBackup(from: data, reason: "Backup Now")
        let createdAt = (try? record.url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? record.date
        return BackupInfo(createdAt: createdAt, byteCount: record.byteCount)
    }

    func clearBackup() throws {
        guard let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }
}