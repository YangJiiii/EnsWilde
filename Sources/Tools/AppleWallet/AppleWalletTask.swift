import Foundation
import AirliftFFI
import Network

enum AppleWalletTask {
    static func run(store: ToolStore, walletStore: AppleWalletStore, onLogUpdate: @escaping (String) -> Void) async throws {
        let enabledCards = walletStore.enabledCards()
        guard !enabledCards.isEmpty else { throw ToolTaskError.generic("No enabled wallet cards to apply") }
        
        guard NetworkStatus.isVPNTunnelPresent() else { throw ToolTaskError.generic("VPN chưa bật.") }
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw ToolTaskError.generic("Không tìm thấy Pairing File.")
        }
        
        onLogUpdate("Đang dò tunnel IP...")
        guard let _ = await AirliftHostResolver.bestAvailable(log: onLogUpdate) else {
            throw ToolTaskError.generic("Không tìm thấy RSD tunnel.")
        }
        
        let tempFolderName = "AirLiftWallet_\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(tempFolderName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Tạo cấu trúc thư mục cho Wallet
        for card in enabledCards {
            let cardBasePath = tempDir.appendingPathComponent("Passes/Cards").appendingPathComponent(card.id)
            try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("pkpass"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("cache"), withIntermediateDirectories: true)
            
            if let bgData = card.backgroundImageData { try bgData.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent(card.cardBackgroundFileName)) }
            if let fData = card.frontFaceImageData { try fData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("FrontFace")) }
            if let pData = card.placeHolderImageData { try pData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("PlaceHolder")) }
            if let prData = card.previewImageData { try prData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("Preview")) }
            if let passJSON = card.loadPassJSON() { try passJSON.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent("pass.json")) }
        }
        
        onLogUpdate("Pushing files via AirTraffic...")
        let srcDir = tempDir.appendingPathComponent("Passes/Cards").path
        let targetParentDir = "/var/mobile/Library/Passes"
        
        // GỌI THẲNG C-FFI CỦA AIRLIFT
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                
                // Callback để hứng log từ Rust
                let logCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { _, msgPtr in
                    guard let msgPtr else { return }
                    let line = String(cString: msgPtr)
                    DispatchQueue.main.async { onLogUpdate("[Airlift] \(line)") }
                }
                
                // al_exploit_write_dir(pairing_path, source_dir, target_dir, log_cb, ctx, out_error)
                let res = al_exploit_write_dir(
                    pairingURL.path,
                    srcDir,
                    targetParentDir + "/Cards",
                    logCallback,
                    nil,
                    &errPtr
                )
                
                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "Airlift Error (Code: \(res))"
                    if let e = errPtr { al_string_free(e) }
                    continuation.resume(throwing: ToolTaskError.generic("AirLift Error: \(msg)"))
                } else {
                    continuation.resume()
                }
            }
        }
        
        onLogUpdate("✅ Wallet applied.")
    }
}