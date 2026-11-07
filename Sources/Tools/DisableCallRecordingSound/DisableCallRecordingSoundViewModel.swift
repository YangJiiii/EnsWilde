//  DisableCallRecordingSoundViewModel.swift
//  EnsWilde

import Foundation
import AirliftFFI
import Network

@MainActor
class DisableCallRecordingSoundViewModel: ObservableObject {
    @Published var isProcessing = false

    private let targetDirectory = "/var/mobile/Library/CallServices/Greetings/default"
    
    // Thư mục lưu backup trong app
    private var backupDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("CallSoundBackups", isDirectory: true)
    }

    private struct ToneFile {
        let originalName: String
        let silentName: String
    }

    private let toneFiles = [
        ToneFile(originalName: "StartDisclosureWithTone.m4a", silentName: "AirBeepStartSilence.m4a"),
        ToneFile(originalName: "StartDisclosure.caf", silentName: "AirBeepStartSilence.caf"),
        ToneFile(originalName: "StopDisclosure.caf", silentName: "AirBeepStopSilence.caf")
    ]
    
    // Link raw Github của bạn cho file im lặng
    private let githubBaseURL = "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde/main/Resources/"

    /// isRestore = true: Khôi phục từ Backup. isRestore = false: Tắt tiếng.
    func apply(store: ToolStore, isRestore: Bool = false, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }

        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."])
        }

        onLogUpdate("Đang dò tunnel IP...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy RSD tunnel."])
        }

        var stagingDir: URL
        
        if isRestore {
            onLogUpdate("Đang lấy file gốc từ bộ nhớ Backup của App...")
            stagingDir = try prepareRestoreFiles()
        } else {
            // 1. Sao lưu file gốc trước khi ghi đè
            onLogUpdate("Đang sao lưu file âm thanh gốc...")
            try backupOriginalFiles()
            
            // 2. Tải file im lặng từ Github
            onLogUpdate("Đang tải file âm thanh im lặng từ GitHub...")
            stagingDir = try await downloadSilentFiles()
        }
        
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        onLogUpdate("Đang ghi đè âm thanh qua Airlift...")
        try await writeDirectory(pairingPath: pairingURL.path, sourceDir: stagingDir.path, onLogUpdate: onLogUpdate)

        let actionName = isRestore ? "khôi phục" : "tắt tiếng"
        onLogUpdate("✅ Đã \(actionName) âm thanh ghi âm cuộc gọi thành công.")
    }

    // MARK: - Backup & Restore Logic

    private func backupOriginalFiles() throws {
        let bq = BadQuery()
        // Xin quyền BadQuery để đọc file trong thư mục hệ thống
        guard bq.grantAccess(atPath: targetDirectory).0 else {
            throw NSError(domain: "AirLift", code: -5, userInfo: [NSLocalizedDescriptionKey: "Không thể xin quyền BadQuery để sao lưu file gốc."])
        }
        
        if !FileManager.default.fileExists(atPath: backupDirectory.path) {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        for tone in toneFiles {
            let remotePath = (targetDirectory as NSString).appendingPathComponent(tone.originalName)
            let backupPath = backupDirectory.appendingPathComponent(tone.originalName).path
            
            // QUAN TRỌNG: Chỉ backup nếu file backup CHƯA TỒN TẠI.
            // Tránh việc user bấm Apply nhiều lần làm ghi đè file backup bằng chính file im lặng.
            if !FileManager.default.fileExists(atPath: backupPath) {
                if FileManager.default.fileExists(atPath: remotePath) {
                    try FileManager.default.copyItem(atPath: remotePath, toPath: backupPath)
                }
            }
        }
    }

    private func prepareRestoreFiles() throws -> URL {
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirliftRestore_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        
        var foundAny = false
        for tone in toneFiles {
            let backupPath = backupDirectory.appendingPathComponent(tone.originalName).path
            let destURL = stagingDir.appendingPathComponent(tone.originalName)
            
            if FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.copyItem(atPath: backupPath, to: destURL)
                foundAny = true
            }
        }
        
        guard foundAny else {
            throw NSError(domain: "AirLift", code: -6, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy file backup nào. Có thể bạn chưa từng Apply tính năng này."])
        }
        
        return stagingDir
    }

    // MARK: - Github Download (Chỉ dùng cho lúc Apply tắt tiếng)
    
    private func downloadSilentFiles() async throws -> URL {
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirliftTones_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for tone in toneFiles {
            guard let url = URL(string: githubBaseURL + tone.silentName) else {
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ cho \(tone.silentName)"])
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không thể tải \(tone.silentName) từ GitHub."])
            }
            
            let destURL = stagingDir.appendingPathComponent(tone.originalName)
            try data.write(to: destURL)
        }

        return stagingDir
    }

    // MARK: - Airlift Write
    
    private func writeDirectory(pairingPath: String, sourceDir: String, onLogUpdate: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }

                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = al_exploit_write_dir(pairingPath, sourceDir, self.targetDirectory, cb, ctx, &errPtr)

                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "Mã lỗi FFI: \(res)"
                    if let e = errPtr { al_string_free(e) }
                    continuation.resume(throwing: NSError(domain: "AirLift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    if let e = errPtr { al_string_free(e) }
                    continuation.resume()
                }
            }
        }
    }
}