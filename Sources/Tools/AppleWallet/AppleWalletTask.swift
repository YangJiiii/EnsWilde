import Foundation
import AirliftFFI
import Network

class LogCallbackContext {
    let onLogUpdate: (String) -> Void
    init(onLogUpdate: @escaping (String) -> Void) {
        self.onLogUpdate = onLogUpdate
    }
}

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
        
        // Tạo cấu trúc thư mục Cards chuẩn
        let cardsDir = tempDir.appendingPathComponent("Cards")
        try FileManager.default.createDirectory(at: cardsDir, withIntermediateDirectories: true)
        
        for card in enabledCards {
            let cardBasePath = cardsDir.appendingPathComponent(card.id)
            try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("pkpass"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cardBasePath.appendingPathExtension("cache"), withIntermediateDirectories: true)
            
            if let bgData = card.backgroundImageData { try bgData.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent(card.cardBackgroundFileName)) }
            if let fData = card.frontFaceImageData { try fData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("FrontFace")) }
            if let pData = card.placeHolderImageData { try pData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("PlaceHolder")) }
            if let prData = card.previewImageData { try prData.write(to: cardBasePath.appendingPathExtension("cache").appendingPathComponent("Preview")) }
            if let passJSON = card.loadPassJSON() { try passJSON.write(to: cardBasePath.appendingPathExtension("pkpass").appendingPathComponent("pass.json")) }
        }
        
        onLogUpdate("Pushing files via AirTraffic (Inject Folder)...")
        let srcDir = cardsDir.path
        let targetParentDir = "/var/mobile/Library/Passes"
        let destName = "Cards"
        
        let logCtx = LogCallbackContext { line in
            onLogUpdate("[Airlift] \(line)")
        }
        let ctxPtr = Unmanaged.passUnretained(logCtx).toOpaque()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                
                let logCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { ctx, msgPtr in
                    guard let ctx = ctx, let msgPtr = msgPtr else { return }
                    let line = String(cString: msgPtr)
                    let logCtx = Unmanaged<LogCallbackContext>.fromOpaque(ctx).takeUnretainedValue()
                    logCtx.onLogUpdate(line)
                }
                
                // SỬ DỤNG HÀM MỚI: al_exploit_inject_folder
                let res = al_exploit_inject_folder(
                    pairingURL.path,
                    srcDir,
                    targetParentDir,
                    destName,
                    logCallback,
                    ctxPtr,
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