//  DisableCallRecordingSoundViewModel.swift
//  EnsWilde

import Foundation
import AirliftFFI
import Network

@MainActor
class DisableCallRecordingSoundViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var currentStatus: String = "Checking..."
    @Published var isTweakActive: Bool = false

    private let targetDirectory = "/var/mobile/Library/CallServices/Greetings/default"
    
    // Thư mục lưu file gốc trong App
    var backupDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("AirBeepBackups", isDirectory: true)
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
    
    private let githubBaseURL = "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde/main/Resources/"

    // MARK: - Check Status
    func checkStatus() {
        let fm = FileManager.default
        let hasBackup = fm.fileExists(atPath: backupDirectory.path)
        var backupCount = 0
        if hasBackup {
            backupCount = (try? fm.contentsOfDirectory(atPath: backupDirectory.path).count) ?? 0
        }
        
        if backupCount >= 3 {
            currentStatus = "Backup Ready (Có thể Restore)"
        } else {
            currentStatus = "No Backup Found"
        }
        isTweakActive = backupCount >= 3
    }
    
    // MARK: - Import Backup
    func importBackupFile(url: URL, fileName: String) throws {
        if !FileManager.default.fileExists(atPath: backupDirectory.path) {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }
        let destURL = backupDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.copyItem(at: url, to: destURL)
        checkStatus()
    }

    // MARK: - Apply / Restore
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

        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirliftTones_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        if isRestore {
            onLogUpdate("Đang lấy file gốc từ bộ nhớ Backup của App...")
            guard isTweakActive else {
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "Chưa có Backup. Hãy Apply lần đầu để App tự động sao lưu."])
            }
            
            for tone in toneFiles {
                let backupURL = backupDirectory.appendingPathComponent(tone.originalName)
                let destURL = stagingDir.appendingPathComponent(tone.originalName)
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.copyItem(at: backupURL, to: destURL)
                }
            }
        } else {
            try await autoBackupIfNeeded(pairingPath: pairingURL.path, onLogUpdate: onLogUpdate)
            
            onLogUpdate("Đang tải file âm thanh im lặng từ GitHub...")
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
        }

        onLogUpdate("Đang ghi đè âm thanh qua Airlift...")
        try await writeDirectory(pairingPath: pairingURL.path, sourceDir: stagingDir.path, onLogUpdate: onLogUpdate)

        let actionName = isRestore ? "khôi phục" : "tắt tiếng"
        onLogUpdate("✅ Đã \(actionName) âm thanh thành công.")
        
        checkStatus()
    }

    // MARK: - Tự động Backup
    private func autoBackupIfNeeded(pairingPath: String, onLogUpdate: @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: backupDirectory.path) {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        for tone in toneFiles {
            let backupPath = backupDirectory.appendingPathComponent(tone.originalName).path
            if fm.fileExists(atPath: backupPath) { continue }
            
            let remotePath = "\(targetDirectory)/\(tone.originalName)"
            var outData: UnsafeMutablePointer<UInt8>? = nil
            var outLen: Int = 0 // FIX: Đã đổi thành Int
            var outErr: UnsafeMutablePointer<CChar>? = nil

            onLogUpdate("[Backup] Đang trích xuất \(tone.originalName)...")
            
            let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
            defer { AirliftFFIBridge.releaseLogCallback(ctx) }

            let res = pairingPath.withCString { pPath in
                remotePath.withCString { rPath in
                    al_exploit_read_file(pPath, rPath, cb, ctx, &outData, &outLen, &outErr)
                }
            }

            if res == 0, let dataPtr = outData, outLen > 0 {
                let data = Data(bytes: dataPtr, count: outLen) // FIX: outLen đã là Int
                try data.write(to: URL(fileURLWithPath: backupPath))
                al_bytes_free(dataPtr, outLen) // FIX: outLen đã là Int
                onLogUpdate("[Backup] ✅ Đã sao lưu \(tone.originalName) (\(outLen) bytes)")
            } else {
                if let errPtr = outErr {
                    let msg = String(cString: errPtr)
                    onLogUpdate("⚠️ Không thể đọc \(tone.originalName): \(msg)")
                    al_string_free(errPtr)
                } else {
                    onLogUpdate("⚠️ Không thể đọc \(tone.originalName) (Mã: \(res))")
                }
            }
        }
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