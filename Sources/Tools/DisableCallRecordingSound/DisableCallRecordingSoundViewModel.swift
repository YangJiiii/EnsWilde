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
        let silentBundleName: String
        let fileExtension: String
    }

    // Ánh xạ file gốc trên máy với file im lặng trong Bundle
    private let toneFiles = [
        ToneFile(originalName: "StartDisclosureWithTone.m4a", silentBundleName: "AirBeepStartSilence", fileExtension: "m4a"),
        ToneFile(originalName: "StartDisclosure.caf", silentBundleName: "AirBeepStartSilence", fileExtension: "caf"),
        ToneFile(originalName: "StopDisclosure.caf", silentBundleName: "AirBeepStopSilence", fileExtension: "caf")
    ]

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

        onLogUpdate("Đang chuẩn bị file âm thanh im lặng...")
        let stagingDir = try prepareSilentFiles()
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        onLogUpdate("Đang ghi đè âm thanh qua Airlift...")
        try await writeDirectory(pairingPath: pairingURL.path, sourceDir: stagingDir.path, onLogUpdate: onLogUpdate)

        onLogUpdate("✅ Đã tắt âm thanh thông báo ghi âm cuộc gọi.")
    }

    private func prepareSilentFiles() throws -> URL {
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirliftTones_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        for tone in toneFiles {
            guard let bundleURL = Bundle.main.url(forResource: tone.silentBundleName, withExtension: tone.fileExtension) else {
                throw NSError(domain: "AirLift", code: -2, userInfo: [NSLocalizedDescriptionKey: "Thiếu file trong bundle: \(tone.silentBundleName).\(tone.fileExtension)"])
            }
            let destURL = stagingDir.appendingPathComponent(tone.originalName)
            try FileManager.default.copyItem(at: bundleURL, to: destURL)
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
