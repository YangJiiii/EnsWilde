//  DisableCallRecordingSoundViewModel.swift
//  EnsWilde

import Foundation
import AirliftFFI
import Network

@MainActor
final class DisableCallRecordingSoundViewModel: ObservableObject {

    // MARK: - Published (View tiêu thụ)
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var currentStatus: String = "Checking..."
    @Published private(set) var isTweakActive: Bool = false

    // Các thuộc tính View đang dùng trực tiếp
    @Published private(set) var isChecking: Bool = false
    @Published private(set) var toneStatus: String = "Unknown"
    @Published private(set) var isToneSilenced: Bool = false
    @Published private(set) var backupStatus: String = "Checking..."
    @Published private(set) var isBackupReady: Bool = false

    // MARK: - Hằng số
    private let targetDirectory = "/var/mobile/Library/CallServices/Greetings/default"
    private let githubBaseURL = "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde/main/Resources/"

    // MARK: - Đường dẫn backup
    var backupDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("AirBeepBackups", isDirectory: true)
    }

    // MARK: - Model
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
        // Đồng bộ state ngay khi khởi tạo, tránh UI hiển thị "Checking..." mãi
        refreshBackupState()
    }

    // MARK: - Backup state
    /// Đọc trạng thái backup từ đĩa và cập nhật toàn bộ @Published liên quan.
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
        isTweakActive = ready
        backupStatus  = currentStatus
        isBackupReady = ready
    }

    /// Public API cho View (giữ đúng tên method View gọi).
    func checkStatus()       { refreshBackupState() }
    func checkBackupStatus() { refreshBackupState() }

    // MARK: - Tone status
    /// Best-effort check trạng thái tone hiện tại.
    /// - Nếu thiếu pairing/VPN: báo lỗi ngay, không block UI.
    /// - Nếu có backup: suy luận tone đã bị silenced (vì lần Apply gần nhất đã ghi file im lặng).
    func checkToneStatus() async {
        isChecking = true
        defer { isChecking = false }

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            toneStatus     = "Pairing file not found"
            isToneSilenced = false
            return
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            toneStatus     = "VPN required"
            isToneSilenced = false
            return
        }

        // Đảm bảo backup state đồng bộ trước khi suy luận
        refreshBackupState()
        toneStatus     = isTweakActive ? "Silenced (tweak active)" : "Original"
        isToneSilenced = isTweakActive
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

        let action = isRestore ? "khôi phục" : "tắt tiếng"
        onLogUpdate("✅ Đã \(action) âm thanh thành công.")
        refreshBackupState()
    }

    // MARK: - Stage bước Restore
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

    // MARK: - Stage bước Apply (tải file silent từ GitHub)
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

    // MARK: - Auto backup 3 file gốc lần đầu Apply
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
            var outData: UnsafeMutablePointer<UInt8>? = nil
            var outLen: Int = 0
            var outErr: UnsafeMutablePointer<CChar>? = nil

            onLogUpdate("[Backup] Đang trích xuất \(tone.originalName)...")

            let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
            defer { AirliftFFIBridge.releaseLogCallback(ctx) }

            // Đảm bảo buffer luôn được free, kể cả khi write lỗi
            defer {
                if let ptr = outData, outLen > 0 {
                    al_bytes_free(ptr, outLen)
                }
                if let e = outErr { al_string_free(e) }
            }

            let res: Int32 = pairingPath.withCString { p in
                remotePath.withCString { r in
                    al_exploit_read_file(p, r, cb, ctx, &outData, &outLen, &outErr)
                }
            }

            if res == 0, let ptr = outData, outLen > 0 {
                let data = Data(bytes: ptr, count: outLen)
                try data.write(to: backupURL)
                onLogUpdate("[Backup] ✅ Đã sao lưu \(tone.originalName) (\(outLen) bytes)")
            } else if let e = outErr {
                onLogUpdate("⚠️ Không thể đọc \(tone.originalName): \(String(cString: e))")
            } else {
                onLogUpdate("⚠️ Không thể đọc \(tone.originalName) (Mã: \(res))")
            }
        }
    }

    // MARK: - Ghi file qua Airlift
    private func writeDirectory(pairingPath: String,
                                sourceDir: String,
                                onLogUpdate: @escaping (String) -> Void) async throws {
        // Chụp targetDirectory trước khi rời MainActor để tránh warning Swift 6
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

    // MARK: - Helper
    // nonisolated: hàm thuần, không đụng state actor, an toàn gọi từ mọi luồng.
    // Đây chính là chỗ sửa warning Swift 6.
    private nonisolated static func makeError(code: Int, msg: String) -> NSError {
        NSError(domain: "AirLift", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}