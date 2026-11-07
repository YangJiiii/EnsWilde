//  DisableCallRecordingSoundViewModel.swift
//  EnsWilde

import Foundation
import AirliftFFI
import Network

@MainActor
final class DisableCallRecordingSoundViewModel: ObservableObject {

    // MARK: - Published state
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var currentStatus: String = "Checking..."

    /// Toggle "tweak đang bật". CHỈ false khi:
    ///   - Chưa Apply lần nào (không có backup)
    ///   - User xoá backup / mất backup
    /// KHÔNG bị tắt sau Restore → vẫn cho phép Apply lại.
    @Published private(set) var isTweakActive: Bool = false

    @Published private(set) var isChecking: Bool = false

    /// Trạng thái THỰC TẾ của 3 file tone trên máy (detect bằng cách đọc file qua Airlift).
    /// true  = file hiện tại KHÁC backup → đã bị ghi silent
    /// false = file hiện tại GIỐNG backup → đang là bản gốc
    @Published private(set) var isToneSilenced: Bool = false

    @Published private(set) var toneStatus: String = "Unknown"
    @Published private(set) var backupStatus: String = "Checking..."
    @Published private(set) var isBackupReady: Bool = false

    // MARK: - Hằng số
    private let targetDirectory = "/var/mobile/Library/CallServices/Greetings/default"
    private let githubBaseURL = "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde/main/Resources/"

    var backupDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("AirBeepBackups", isDirectory: true)
    }

    private struct ToneFile {
        let originalName: String
        let silentName: String
    }

    private let toneFiles: [ToneFile] = [
        ToneFile(originalName: "StartDisclosureWithTone.m4a", silentName: "AirBeepStartSilence.m4a"),
        ToneFile(originalName: "StartDisclosure.caf",         silentName: "AirBeepStartSilence.caf"),
        ToneFile(originalName: "StopDisclosure.caf",          silentName: "AirBeepStopSilence.caf")
    ]

    // MARK: - Init
    init() {
        refreshBackupState()
        // Fallback ban đầu: nếu có backup → coi như đã từng Apply (Silenced).
        // checkToneStatus() sẽ detect lại chính xác từ file thực tế khi user mở tab.
        if isBackupReady {
            isTweakActive = true
            isToneSilenced = true
            toneStatus = "Silenced (tweak active)"
        } else {
            isTweakActive = false
            isToneSilenced = false
            toneStatus = "Original"
        }
    }

    // MARK: - Backup state
    private func refreshBackupState() {
        let fm = FileManager.default
        let backupCount: Int
        if fm.fileExists(atPath: backupDirectory.path) {
            backupCount = (try? fm.contentsOfDirectory(atPath: backupDirectory.path).count) ?? 0
        } else {
            backupCount = 0
        }

        let ready = backupCount >= toneFiles.count
        currentStatus = ready ? "Backup Ready (Có thể Restore)" : "No Backup Found"
        backupStatus  = currentStatus
        isBackupReady = ready

        // Chỉ tắt toggle khi mất backup. Có backup → giữ nguyên isTweakActive (không reset).
        if !ready {
            isTweakActive = false
        }
    }

    func checkStatus()       { refreshBackupState() }
    func checkBackupStatus() { refreshBackupState() }

    // MARK: - Tone status — DETECT thực tế bằng đọc file qua Airlift
    func checkToneStatus() async {
        isChecking = true
        defer { isChecking = false }

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            toneStatus = "Pairing file not found"
            return
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            toneStatus = "VPN required"
            return
        }

        refreshBackupState()

        // Đọc 3 file trên máy qua Airlift → so sánh với backup → detect chính xác.
        if let detected = await detectToneSilenceState(pairingPath: pairingURL.path) {
            isToneSilenced = detected
            // Có file backup → user đã từng Apply → toggle phải ON.
            if isBackupReady {
                isTweakActive = true
            }
        }

        toneStatus = isToneSilenced ? "Silenced (tweak active)" : "Original"
    }

    // MARK: - Detect state bằng cách đọc file thực tế
    /// Trả về:
    ///   true  = tất cả 3 file hiện tại KHÁC backup → đang silenced
    ///   false = tất cả 3 file hiện tại GIỐNG backup → đang original
    ///   nil   = không đọc được / lẫn lộn → giữ state cũ
    private func detectToneSilenceState(pairingPath: String) async -> Bool? {
        let fm = FileManager.default
        var silencedCount = 0
        var originalCount = 0

        for tone in toneFiles {
            let backupURL = backupDirectory.appendingPathComponent(tone.originalName)
            guard fm.fileExists(atPath: backupURL.path),
                  let backupData = try? Data(contentsOf: backupURL) else {
                continue
            }

            let remotePath = "\(targetDirectory)/\(tone.originalName)"
            guard let currentData = await readRemoteFile(pairingPath: pairingPath,
                                                         remotePath: remotePath) else {
                continue
            }

            if currentData == backupData {
                originalCount += 1
            } else {
                silencedCount += 1
            }
        }

        if silencedCount > 0 && originalCount == 0 { return true }
        if originalCount > 0 && silencedCount == 0 { return false }
        return nil
    }

    /// Đọc 1 file remote qua AirliftFFI.
    private func readRemoteFile(pairingPath: String, remotePath: String) async -> Data? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var outData: UnsafeMutablePointer<UInt8>? = nil
                var outLen: Int = 0
                var outErr: UnsafeMutablePointer<CChar>? = nil

                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: { _ in })
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                defer {
                    if let ptr = outData, outLen > 0 { al_bytes_free(ptr, outLen) }
                    if let e = outErr { al_string_free(e) }
                }

                let res: Int32 = pairingPath.withCString { p in
                    remotePath.withCString { r in
                        al_exploit_read_file(p, r, cb, ctx, &outData, &outLen, &outErr)
                    }
                }

                if res == 0, let ptr = outData, outLen > 0 {
                    cont.resume(returning: Data(bytes: ptr, count: outLen))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Import backup thủ công (nếu cần)
    func importBackupFile(url: URL, fileName: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: backupDirectory.path) {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }
        let destURL = backupDirectory.appendingPathComponent(fileName)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: url, to: destURL)
        refreshBackupState()
    }

    // MARK: - Apply / Restore
    func apply(store: ToolStore,
               isRestore: Bool = false,
               onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw Self.makeError(code: -1, msg: "Không tìm thấy Pairing File.")
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw Self.makeError(code: -10, msg: "VPN chưa bật.")
        }

        onLogUpdate("Đang dò tunnel IP...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw Self.makeError(code: -3, msg: "Không tìm thấy RSD tunnel.")
        }

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirliftTones_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        if isRestore {
            try await stageRestore(into: stagingDir, onLogUpdate: onLogUpdate)
        } else {
            try await autoBackupIfNeeded(pairingPath: pairingURL.path, onLogUpdate: onLogUpdate)
            try await stageSilentFiles(into: stagingDir, onLogUpdate: onLogUpdate)
        }

        onLogUpdate("Đang ghi đè âm thanh qua Airlift...")
        try await writeDirectory(pairingPath: pairingURL.path,
                                 sourceDir: stagingDir.path,
                                 onLogUpdate: onLogUpdate)

        // ─────────────────────────────────────────────────────────────
        // Cập nhật state sau khi ghi thành công
        // ─────────────────────────────────────────────────────────────
        if isRestore {
            isToneSilenced = false
            toneStatus     = "Original"
            isTweakActive  = true   // ← giữ toggle ON (nếu có backup)
        } else {
            isToneSilenced = true
            toneStatus     = "Silenced (tweak active)"
            isTweakActive  = true
        }

        onLogUpdate("✅ Đã \(isRestore ? "khôi phục" : "tắt tiếng") âm thanh thành công.")
        refreshBackupState()

        // Verify lại bằng cách đọc file thực tế (best-effort, không throw nếu fail)
        if let detected = await detectToneSilenceState(pairingPath: pairingURL.path) {
            isToneSilenced = detected
            toneStatus = detected ? "Silenced (tweak active)" : "Original"
        }
        if isBackupReady {
            isTweakActive = true
        }
    }

    private func stageRestore(into stagingDir: URL,
                              onLogUpdate: @escaping (String) -> Void) async throws {
        onLogUpdate("Đang lấy file gốc từ bộ nhớ Backup của App...")
        refreshBackupState()
        guard isBackupReady else {
            throw Self.makeError(code: -2,
                msg: "Chưa có Backup. Hãy Apply lần đầu để App tự động sao lưu.")
        }

        let fm = FileManager.default
        for tone in toneFiles {
            let src  = backupDirectory.appendingPathComponent(tone.originalName)
            let dest = stagingDir.appendingPathComponent(tone.originalName)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: dest)
        }
    }

    private func stageSilentFiles(into stagingDir: URL,
                                  onLogUpdate: @escaping (String) -> Void) async throws {
        onLogUpdate("Đang tải file âm thanh im lặng từ GitHub...")
        for tone in toneFiles {
            guard let url = URL(string: githubBaseURL + tone.silentName) else {
                throw Self.makeError(code: -2, msg: "URL không hợp lệ cho \(tone.silentName)")
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Self.makeError(code: -2, msg: "Không thể tải \(tone.silentName) từ GitHub.")
            }
            try data.write(to: stagingDir.appendingPathComponent(tone.originalName))
        }
    }

    private func autoBackupIfNeeded(pairingPath: String,
                                    onLogUpdate: @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: backupDirectory.path) {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        for tone in toneFiles {
            let backupURL = backupDirectory.appendingPathComponent(tone.originalName)
            if fm.fileExists(atPath: backupURL.path) { continue }

            let remotePath = "\(targetDirectory)/\(tone.originalName)"
            onLogUpdate("[Backup] Đang trích xuất \(tone.originalName)...")

            if let data = await readRemoteFile(pairingPath: pairingPath, remotePath: remotePath) {
                try data.write(to: backupURL)
                onLogUpdate("[Backup] ✅ Đã sao lưu \(tone.originalName) (\(data.count) bytes)")
            } else {
                onLogUpdate("⚠️ Không thể đọc \(tone.originalName) để backup")
            }
        }
    }

    private func writeDirectory(pairingPath: String,
                                sourceDir: String,
                                onLogUpdate: @escaping (String) -> Void) async throws {
        let target = self.targetDirectory

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }

                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = al_exploit_write_dir(pairingPath, sourceDir, target, cb, ctx, &errPtr)

                if res != 0 {
                    let msg = errPtr.map { String(cString: $0) } ?? "Mã lỗi FFI: \(res)"
                    if let e = errPtr { al_string_free(e) }
                    cont.resume(throwing: Self.makeError(code: Int(res), msg: msg))
                } else {
                    if let e = errPtr { al_string_free(e) }
                    cont.resume()
                }
            }
        }
    }

    private nonisolated static func makeError(code: Int, msg: String) -> NSError {
        NSError(domain: "AirLift", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}