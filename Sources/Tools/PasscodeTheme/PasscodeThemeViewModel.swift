//  PasscodeThemeViewModel.swift
//  EnsWilde
//
//  Full implementation: Import, Apply (via Airlift), and Reset (Reboot device).

import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

@MainActor
class PasscodeThemeViewModel: ObservableObject {

    @Published var isProcessing = false
    private let store: PasscodeThemeStore

    init(store: PasscodeThemeStore) {
        self.store = store
    }

    // MARK: - Import

    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let result = try await Task.detached(priority: .userInitiated) {
            () -> (PasscodeTheme, PasscodeTheme.DetectedSize) in
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: tempFileURL) }

            do {
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: tempFileURL)
            } catch {
                throw PasscodeThemeError.accessDenied
            }

            let newTheme = PasscodeTheme(name: name)
            let themeFolder = newTheme.themeFolderURL
            if !FileManager.default.fileExists(atPath: themeFolder.path) {
                try FileManager.default.createDirectory(at: themeFolder,
                                                        withIntermediateDirectories: true)
            }

            let detectedSize = PasscodeThemeViewModel.detectSizeFromZIP(at: tempFileURL)

            do {
                try FileManager.default.unzipItem(at: tempFileURL, to: themeFolder)
            } catch {
                try? FileManager.default.removeItem(at: themeFolder)
                throw PasscodeThemeError.invalidFormat
            }

            try PasscodeThemeViewModel.extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
            return (newTheme, detectedSize)
        }.value

        var themeWithSize = result.0
        themeWithSize.detectedSize = result.1
        self.store.addTheme(themeWithSize)
    }

    /// Hàm tương thích với View call site cũ
    func importDefaultPasscode(
        from sourceURL: URL,
        name: String,
        themeStore: PasscodeThemeStore
    ) async throws {
        try await importTheme(from: sourceURL, name: name)
    }

    // MARK: - Xử lý ảnh

    nonisolated func processThemeFiles(
        theme: PasscodeTheme,
        globalPrefix: PasscodeTheme.PrefixLanguage
    ) throws -> [(sourceURL: URL, processedData: Data, targetFilename: String)] {

        var processedFiles: [(URL, Data, String)] = []
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else { throw PasscodeThemeError.noImagesFound }

        for filename in imageFiles {
            let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
            guard let firstHyphen = filename.firstIndex(of: "-") else { continue }
            let suffix = String(filename[firstHyphen...])
            let newFilename = globalPrefix.rawValue + suffix

            guard let image = UIImage(contentsOfFile: sourceURL.path) else { continue }
            let processedImage = resizeImage(image,
                                             for: theme.keySize,
                                             detectedSize: theme.detectedSize)
            guard let imageData = processedImage.pngData() else { continue }

            processedFiles.append((sourceURL, imageData, newFilename))
        }
        return processedFiles
    }

    nonisolated private func resizeImage(
        _ image: UIImage,
        for keySize: PasscodeTheme.KeySize,
        detectedSize: PasscodeTheme.DetectedSize
    ) -> UIImage {

        var sizeMultiplier: CGFloat = 1.0

        if detectedSize == .small && keySize == .big {
            sizeMultiplier = 287.0 / 202.0
        } else if detectedSize == .big && keySize == .small {
            sizeMultiplier = 202.0 / 287.0
        } else {
            return image
        }

        if abs(sizeMultiplier - 1.0) < PasscodeTheme.KeySize.resizeThreshold {
            return image
        }

        let currentSize = image.size
        guard currentSize.width > 0 && currentSize.height > 0 else { return image }

        let targetPixelSize = CGSize(
            width: currentSize.width * sizeMultiplier * image.scale,
            height: currentSize.height * sizeMultiplier * image.scale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetPixelSize))
        }
    }

    nonisolated static private func detectSizeFromZIP(
        at zipURL: URL
    ) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for entry in archive {
                if entry.path.hasSuffix("_small") { return .small }
            }
            for entry in archive {
                if entry.path.hasSuffix("_big") { return .big }
            }
            return .unknown
        } catch {
            return .unknown
        }
    }

    nonisolated static private func extractImagesFromTelephonySubfolder(
        themeFolder: URL
    ) throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) else { return }

        guard let telephonyFolder = contents.first(where: {
            $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI")
        }) else { return }

        let telephonyFolderURL = themeFolder.appendingPathComponent(telephonyFolder)
        guard let imageFiles = try? fm.contentsOfDirectory(atPath: telephonyFolderURL.path) else { return }

        for filename in imageFiles {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            try? fm.moveItem(at: telephonyFolderURL.appendingPathComponent(filename),
                             to: themeFolder.appendingPathComponent(filename))
        }
        try? fm.removeItem(at: telephonyFolderURL)
    }

    // MARK: - Apply Theme

    func applyTheme(
        _ theme: PasscodeTheme,
        store: ToolStore,
        onLogUpdate: @escaping (String) -> Void
    ) async throws {

        isProcessing = true
        defer { isProcessing = false }

        let globalTelephony = self.store.globalTelephonyVersion
        let globalPrefix   = self.store.globalCustomPrefix

        onLogUpdate("Preparing Passcode Theme...")

        // 1. Xử lý ảnh
        let processedFiles = try processThemeFiles(theme: theme, globalPrefix: globalPrefix)
        guard !processedFiles.isEmpty else {
            throw PasscodeThemeError.noImagesProcessed
        }

        // 2. Pairing file
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }

        // 3. Thư mục tạm
        let tempFolderName = "AirLiftPayload_\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempFolderName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for (_, imageData, targetFilename) in processedFiles {
            try imageData.write(to: tempDir.appendingPathComponent(targetFilename))
        }

        // 4. Target path
        var targetPath = globalTelephony.cachePath
        if targetPath.hasSuffix("/") {
            targetPath = String(targetPath.dropLast())
        }

        // 5. Xoá cache cũ
        onLogUpdate("Clearing old cache at \(targetPath)...")
        let bq = BadQuery()
        if bq.grantAccess(atPath: targetPath).0 {
            do {
                if FileManager.default.fileExists(atPath: targetPath) {
                    try FileManager.default.removeItem(atPath: targetPath)
                }
                try FileManager.default.createDirectory(atPath: targetPath,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
                onLogUpdate("✅ Cleared old cache successfully.")
            } catch {
                onLogUpdate("⚠️ Warning: Could not clear cache completely. \(error.localizedDescription)")
            }
        }

        // 6. Resolve target host (RSD 49152 + Lockdown 62078 probe)
        onLogUpdate("Đang dò tunnel IP + probe RSD 49152 / Lockdown 62078...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Không kết nối được tới VPN. Hãy kiểm tra LocalDevVPN đã Connected chưa."])
        }

        // 7. Gọi Airlift FFI
        onLogUpdate("Đang ghi qua AirTraffic...")
        let pairingPath = pairingURL.path
        let srcDir      = tempDir.path

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }

                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = al_exploit_write_dir(
                    pairingPath,
                    srcDir,
                    targetPath,
                    cb,
                    ctx,
                    &errPtr
                )

                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "Mã lỗi FFI: \(res)"
                    if let e = errPtr { al_string_free(e) }
                    continuation.resume(throwing: NSError(
                        domain: "AirLift",
                        code: Int(res),
                        userInfo: [NSLocalizedDescriptionKey: msg]
                    ))
                } else {
                    if let e = errPtr { al_string_free(e) }
                    continuation.resume()
                }
            }
        }

        onLogUpdate("✅ Passcode applied successfully.")
    }

    // MARK: - Reset Theme (Xoá cache & Reboot)

    func resetTheme(
        store: ToolStore,
        onLogUpdate: @escaping (String) -> Void
    ) async throws {
        
        isProcessing = true
        defer { isProcessing = false }
        
        let globalTelephony = self.store.globalTelephonyVersion
        var targetPath = globalTelephony.cachePath
        if targetPath.hasSuffix("/") {
            targetPath = String(targetPath.dropLast())
        }
        
        onLogUpdate("Đang tiến hành Reset Passcode Theme...")
        
        // 1. Xoá thư mục cache TelephonyUI bằng BadQuery
        let bq = BadQuery()
        if bq.grantAccess(atPath: targetPath).0 {
            do {
                if FileManager.default.fileExists(atPath: targetPath) {
                    try FileManager.default.removeItem(atPath: targetPath)
                }
                try FileManager.default.createDirectory(atPath: targetPath,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
                onLogUpdate("✅ Đã xoá Passcode Theme thành công.")
            } catch {
                onLogUpdate("⚠️ Lỗi khi xoá cache: \(error.localizedDescription)")
                throw error
            }
        } else {
            throw NSError(domain: "AirLift", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Không thể xin quyền xoá file (BadQuery failed)."])
        }
        
        // 2. Gọi Reboot thiết bị
        onLogUpdate("🔄 Đang khởi động lại thiết bị (Reboot)...")
        try await Task.sleep(nanoseconds: 800_000_000) // Đợi 0.8s để log kịp hiện lên UI
        
        // Gọi hàm Reboot
        RebootHelper.rebootDevice()
    }
}

// MARK: - Errors

enum PasscodeThemeError: LocalizedError {
    case accessDenied, noImagesFound, noImagesProcessed, invalidFormat

    var errorDescription: String? {
        switch self {
        case .accessDenied:      return "Không có quyền truy cập file."
        case .noImagesFound:     return "Không tìm thấy ảnh."
        case .noImagesProcessed: return "Không xử lý được ảnh."
        case .invalidFormat:     return "Định dạng theme không hợp lệ."
        }
    }
}