//  DisableCallRecordingSoundViewModel.swift
//  EnsWilde

import Foundation
import AirliftFFI
import Network

@MainActor
class DisableCallRecordingSoundViewModel: ObservableObject {
    @Published var isProcessing = false

    private let targetDirectory = "/var/mobile/Library/CallServices/Greetings/default"

    private struct ToneFile {
        let originalName: String
        let remoteName: String
    }

    // Ánh xạ file trên máy với file tải từ GitHub
    private let toneFiles = [
        ToneFile(originalName: "StartDisclosureWithTone.m4a", remoteName: "AirBeepStartSilence.m4a"),
        ToneFile(originalName: "StartDisclosure.caf", remoteName: "AirBeepStartSilence.caf"),
        ToneFile(originalName: "StopDisclosure.caf", remoteName: "AirBeepStopSilence.caf")
    ]
    
    // Link raw Github của bạn
    private let githubBaseURL = "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde/main/Resources/"

    func apply(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
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

        onLogUpdate("Đang tải file âm thanh im lặng từ GitHub...")
        let stagingDir = try await downloadSilentFiles()
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        onLogUpdate("Đang ghi đè âm thanh qua Airlift...")
        try await writeDirectory(pairingPath: pairingURL.path, sourceDir: stagingDir.path, onLogUpdate: onLogUpdate)

        onLogUpdate("✅ Đã tắt âm thanh thông báo ghi âm cuộc gọi.")
    }

    private func downloadSilentFiles() async throws -> URL {
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirliftTones_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for tone in toneFiles {
            guard let url = URL(string: githubBaseURL + tone.remoteName) else {
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ cho \(tone.remoteName)"])
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không thể tải \(tone.remoteName) từ GitHub. Hãy kiểm tra lại repo."])
            }
            
            let destURL = stagingDir.appendingPathComponent(tone.originalName)
            try data.write(to: destURL)
        }

        return stagingDir
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