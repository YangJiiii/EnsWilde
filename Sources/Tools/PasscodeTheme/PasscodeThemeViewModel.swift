import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

private var airliftLogSink: ((String) -> Void)?

@MainActor
class PasscodeThemeViewModel: ObservableObject {
    @Published var isProcessing = false
    private let store: PasscodeThemeStore
    
    init(store: PasscodeThemeStore) {
        self.store = store
    }
    
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
        try? FileManager.default.removeItem(at: tempFileURL)
        do { try FileManager.default.copyItem(at: sourceURL, to: tempFileURL) } catch { throw PasscodeThemeError.accessDenied }
        
        let newTheme = PasscodeTheme(name: name)
        let themeFolder = newTheme.themeFolderURL
        if !FileManager.default.fileExists(atPath: themeFolder.path) {
            try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        }
        let detectedSize = detectSizeFromZIP(at: tempFileURL)
        do { try FileManager.default.unzipItem(at: tempFileURL, to: themeFolder) } catch {
            try? FileManager.default.removeItem(at: themeFolder)
            throw PasscodeThemeError.invalidFormat
        }
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        try? FileManager.default.removeItem(at: tempFileURL)
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    // FIX: mark nonisolated để có thể gọi mà không cần await ở bất cứ context nào
    nonisolated func processThemeFiles(theme: PasscodeTheme, globalPrefix: PasscodeTheme.PrefixLanguage) throws -> [(sourceURL: URL, processedData: Data, targetFilename: String)] {
        var processedFiles: [(URL, Data, String)] = []
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else { throw PasscodeThemeError.noImagesFound }
        for filename in imageFiles {
            let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
            guard let firstHyphen = filename.firstIndex(of: "-") else { continue }
            let suffix = String(filename[firstHyphen...])
            let newFilename = globalPrefix.rawValue + suffix
            guard let image = UIImage(contentsOfFile: sourceURL.path) else { continue }
            let processedImage = resizeImage(image, for: theme.keySize, detectedSize: theme.detectedSize)
            guard let imageData = processedImage.pngData() else { continue }
            processedFiles.append((sourceURL, imageData, newFilename))
        }
        return processedFiles
    }
    
    nonisolated private func resizeImage(_ image: UIImage, for keySize: PasscodeTheme.KeySize, detectedSize: PasscodeTheme.DetectedSize) -> UIImage {
        var sizeMultiplier: CGFloat = 1.0
        if detectedSize == .small && keySize == .big { sizeMultiplier = 287.0 / 202.0 }
        else if detectedSize == .big && keySize == .small { sizeMultiplier = 202.0 / 287.0 }
        else { return image }
        if abs(sizeMultiplier - 1.0) < PasscodeTheme.KeySize.resizeThreshold { return image }
        let currentSize = image.size
        guard currentSize.width > 0 && currentSize.height > 0 else { return image }
        let targetPixelSize = CGSize(width: currentSize.width * sizeMultiplier * image.scale, height: currentSize.height * sizeMultiplier * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetPixelSize)) }
    }
    
    nonisolated private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for entry in archive { if entry.path.hasSuffix("_small") { return .small } }
            for entry in archive { if entry.path.hasSuffix("_big") { return .big } }
            return .unknown
        } catch { return .unknown }
    }
    
    nonisolated private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) else { return }
        guard let telephonyFolder = contents.first(where: { $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI") }) else { return }
        let telephonyFolderURL = themeFolder.appendingPathComponent(telephonyFolder)
        guard let imageFiles = try? fm.contentsOfDirectory(atPath: telephonyFolderURL.path) else { return }
        for filename in imageFiles {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            try? fm.moveItem(at: telephonyFolderURL.appendingPathComponent(filename), to: themeFolder.appendingPathComponent(filename))
        }
        try? fm.removeItem(at: telephonyFolderURL)
    }
    
    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {}
    
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        // FIX: Capture mọi thứ cần thiết TRƯỚC khi đẩy C-FFI ra background
        let globalTelephony = self.store.globalTelephonyVersion
        let globalPrefix = self.store.globalCustomPrefix
        
        onLogUpdate("Preparing Passcode Theme...")
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."])
        }
        
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        
        let tempFolderName = "AirLiftPayload_\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(tempFolderName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        for (_, imageData, targetFilename) in processedFiles {
            try imageData.write(to: tempDir.appendingPathComponent(targetFilename))
        }
        
        var targetPath = globalTelephony.cachePath
        if targetPath.hasSuffix("/") { targetPath = String(targetPath.dropLast()) }
        
        onLogUpdate("Ensuring target directory exists...")
        _ = BadQuery().grantAccess(atPath: targetPath)
        
        onLogUpdate("Đang dò tunnel IP...")
        guard let _ = await AirliftHostResolver.bestAvailable(log: onLogUpdate) else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy RSD tunnel."])
        }
        
        onLogUpdate("Đang ghi qua AirTraffic...")
        let pairingPath = pairingURL.path
        let srcDir = tempDir.path
        
        // FIX: Chỉ đẩy cái gọi C-FFI vào background, mọi thứ khác ở MainActor
        try await Task.detached(priority: .userInitiated) {
            airliftLogSink = { message in
                DispatchQueue.main.async { onLogUpdate(message) }
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var errPtr: UnsafeMutablePointer<CChar>? = nil
                    
                    let logCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { _, msgPtr in
                        guard let msgPtr else { return }
                        airliftLogSink?(String(cString: msgPtr))
                    }
                    
                    let res = al_exploit_write_dir(
                        pairingPath,
                        srcDir,
                        targetPath,
                        logCallback,
                        nil,
                        &errPtr
                    )
                    
                    if res != 0 {
                        let msg = errPtr != nil ? String(cString: errPtr!) : "Mã lỗi FFI: \(res)"
                        if let e = errPtr { al_string_free(e) }
                        continuation.resume(throwing: NSError(domain: "AirLift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                    } else {
                        continuation.resume()
                    }
                }
            }
            
            airliftLogSink = nil
        }.value
        
        onLogUpdate("✅ Passcode applied successfully.")
    }
}

enum PasscodeThemeError: LocalizedError {
    case accessDenied, noImagesFound, noImagesProcessed, invalidFormat
    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Không có quyền truy cập file."
        case .noImagesFound: return "Không tìm thấy ảnh."
        case .noImagesProcessed: return "Không xử lý được ảnh."
        case .invalidFormat: return "Định dạng theme không hợp lệ."
        }
    }
}