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
            let pkpassDir = cardsDir.appendingPathComponent(card.id).appendingPathExtension("pkpass")
            let cacheDir = cardsDir.appendingPathComponent(card.id).appendingPathExtension("cache")
            
            try FileManager.default.createDirectory(at: pkpassDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            
            // Ghi ảnh nền (nếu có)
            if let bgData = card.backgroundImageData { 
                try bgData.write(to: pkpassDir.appendingPathComponent(card.cardBackgroundFileName)) 
            }
            
            // Do UI mới chỉ chọn 1 ảnh, ta map nó cho cả 3
            let unifiedImage = card.frontFaceImageData ?? card.previewImageData ?? card.backgroundImageData
            if let imgData = unifiedImage {
                try imgData.write(to: cacheDir.appendingPathComponent("FrontFace"))
                try imgData.write(to: cacheDir.appendingPathComponent("PlaceHolder"))
                try imgData.write(to: cacheDir.appendingPathComponent("Preview"))
            }
            
            // Ghi pass.json
            if let passJSON = card.loadPassJSON() { 
                try passJSON.write(to: pkpassDir.appendingPathComponent("pass.json")) 
            }
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