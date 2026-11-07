import Foundation
import AirliftFFI
import Network

@MainActor
class DisableCallRecordingSoundViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var isChecking = false
    
    @Published var toneStatus: String = "Unknown"
    @Published var isToneSilenced: Bool = false
    
    @Published var backupStatus: String = "Unknown"
    @Published var isBackupReady: Bool = false

    private let targetDirectory = "/var/mobile/Library/CallServices/Greetings/default"
    
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

    // MARK: - 1. Check Tone Status (Đọc file thực tế từ máy)
    func checkToneStatus() async {
        isChecking = true
        defer { isChecking = false }
        
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path), NetworkStatus.isVPNTunnelPresent() else {
            toneStatus = "Cần VPN & Pairing File"
            isToneSilenced = false
            return
        }
        
        guard await AirliftHostResolver.bestAvailable(log: { _ in }) != nil else {
            toneStatus = "Không tìm thấy RSD Tunnel"
            isToneSilenced = false
            return
        }

        // Đọc file StartDisclosureWithTone.m4a để check dung lượng
        let remotePath = "\(targetDirectory)/StartDisclosureWithTone.m4a"
        var outData: UnsafeMutablePointer<UInt8>? = nil
        var outLen: UInt = 0
        var outErr: UnsafeMutablePointer<CChar>? = nil
        
        let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: { _ in })
        defer { AirliftFFIBridge.releaseLogCallback(ctx) }

        let res = pairingURL.path.withCString { pPath in
            remotePath.withCString { rPath in
                al_exploit_read_file(pPath, rPath, cb, ctx, &outData, &outLen, &outErr)
            }
        }

        if res == 0, let dataPtr = outData {
            let size = Int(outLen)
            al_bytes_free(dataPtr, outLen) // Giải phóng
            
            // File im lặng của AirBeep thường rất nhỏ (< 10KB)
            // File gốc của Apple thường > 50KB
            if size < 15000 {
                isToneSilenced = true
                toneStatus = "Silenced (Đã tắt tiếng - \(size) bytes)"
            } else {
                isToneSilenced = false
                toneStatus = "Original (Âm thanh gốc - \(size) bytes)"
            }
        } else {
            if let errPtr = outErr {
                toneStatus = "Lỗi: \(String(cString: errPtr))"
                al_string_free(errPtr)
            } else {
                toneStatus = "Không thể đọc file (Code: \(res))"
            }
            isToneSilenced = false
        }
    }

    // MARK: - 2. Check Backup Status
    func checkBackupStatus() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupDirectory.path) else {
            backupStatus = "Chưa có Backup"
            isBackupReady = false
            return
        }
        
        let neededCount = toneFiles.filter { fm.fileExists(atPath: backupDirectory.appendingPathComponent($0.originalName).path) }.count
        
        if neededCount >= 2 {
            isBackupReady = true
            backupStatus = "Đã có Backup (\(neededCount)/3 files)"
        } else {
            isBackupReady = false
            backupStatus = "Backup chưa đủ (\(neededCount)/3 files)"
        }
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
            guard isBackupReady else {
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "Chưa có Backup. Hãy bật Tweak và Apply lần đầu để App tự động sao lưu."])
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
        
        checkBackupStatus()
        await checkToneStatus()
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
            var outLen: UInt = 0
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
                let data = Data(bytes: dataPtr, count: Int(outLen))
                try data.write(to: URL(fileURLWithPath: backupPath))
                al_bytes_free(dataPtr, outLen)
                onLogUpdate("[Backup] ✅ Đã sao lưu \(tone.originalName) (\(outLen) bytes)")
            } else {
                if let errPtr = outErr {
                    let msg = String(cString: errPtr)
                    onLogUpdate("⚠️ Không thể đọc \(tone.originalName): \(msg)")
                    al_string_free(errPtr)
                }
            }
        }
    }

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