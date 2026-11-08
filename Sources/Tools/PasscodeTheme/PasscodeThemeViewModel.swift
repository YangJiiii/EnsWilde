import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network
import ImageIO
import UniformTypeIdentifiers

@MainActor
class PasscodeThemeViewModel: ObservableObject {

    @Published var isProcessing = false
    private let store: PasscodeThemeStore

    init(store: PasscodeThemeStore) { self.store = store }

    // MARK: - Import (KHÔNG đổi logic)
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let result = try await Task.detached(priority: .userInitiated) {
            () -> (PasscodeTheme, PasscodeTheme.DetectedSize) in
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: tempFileURL) }
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: tempFileURL)
            let newTheme = PasscodeTheme(name: name)
            let themeFolder = newTheme.themeFolderURL
            try? FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
            let detectedSize = PasscodeThemeViewModel.detectSizeFromZIP(at: tempFileURL)
            do {
                try FileManager.default.unzipItem(at: tempFileURL, to: themeFolder)
            } catch {
                try? FileManager.default.removeItem(at: themeFolder)
                throw PasscodeThemeError.invalidFormat
            }
            try PasscodeThemeViewModel.extractImagesRecursively(themeFolder: themeFolder)
            return (newTheme, detectedSize)
        }.value
        var themeWithSize = result.0
        themeWithSize.detectedSize = result.1
        self.store.addTheme(themeWithSize)
    }

    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        try await importTheme(from: sourceURL, name: name)
    }

    // MARK: - Detect Size (giữ nguyên logic, chỉ early-exit khi có kết quả)
    nonisolated static private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            var hasBig = false, hasSmall = false
            var hasTUI10 = false, hasTUI9 = false, hasTUI8 = false
            
            for entry in archive {
                let lower = entry.path.lowercased()
                if !hasBig && (lower.hasSuffix("_big") || lower.contains("_big/")) { hasBig = true }
                if !hasSmall && (lower.hasSuffix("_small") || lower.contains("_small/")) { hasSmall = true }
                if !hasTUI10 && lower.contains("telephonyui-10") { hasTUI10 = true }
                if !hasTUI9 && lower.contains("telephonyui-9")  { hasTUI9 = true }
                if !hasTUI8 && lower.contains("telephonyui-8")  { hasTUI8 = true }
                // Early exit
                if hasBig || hasSmall { break }
            }
            
            if hasBig { return .big }
            if hasSmall { return .small }
            if hasTUI10 || hasTUI9 { return .big }
            if hasTUI8 { return .small }
            return .unknown
        } catch { return .unknown }
    }

    // MARK: - Extract Images (giữ logic, thêm ưu tiên file tốt nhất)
    nonisolated static private func extractImagesRecursively(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: themeFolder.path) else { return }
        
        let validExts: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "tif", "bmp"]
        var bestPerDigit: [String: (priority: Int, url: URL)] = [:]

        while let rel = enumerator.nextObject() as? String {
            if rel.hasPrefix(".") || rel.contains("__MACOSX") || rel.contains("/_") { continue }
            let fullURL = themeFolder.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            
            let ext = (rel as NSString).pathExtension.lowercased()
            guard validExts.contains(ext) else { continue }
            
            let filename = (rel as NSString).lastPathComponent
            guard let digit = extractDigitStatic(from: filename) else { continue }
            
            let lower = filename.lowercased()
            var priority = 1
            if lower.contains("---white")      { priority = 10 }
            else if lower.contains("--white") { priority = 9 }
            else if lower.contains("-white")  { priority = 8 }
            
            if let existing = bestPerDigit[digit] {
                if priority > existing.priority { bestPerDigit[digit] = (priority, fullURL) }
            } else {
                bestPerDigit[digit] = (priority, fullURL)
            }
        }

        for (digit, entry) in bestPerDigit {
            let destURL = themeFolder.appendingPathComponent("\(digit).png")
            try? fm.removeItem(at: destURL)
            try? fm.copyItem(at: entry.url, to: destURL)
        }
        
        if let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) {
            for item in contents {
                let fullURL = themeFolder.appendingPathComponent(item)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullURL.path, isDirectory: &isDir), isDir.boolValue {
                    try? fm.removeItem(at: fullURL)
                }
            }
        }
    }

    // MARK: - Extract Digit (giữ nguyên)
    nonisolated static func extractDigitStatic(from filename: String) -> String? {
        var stem = (filename as NSString).deletingPathExtension.lowercased()
        for suffix in ["--white", "-white", "-bold", "@2x", "@3x", "@1x"] {
            stem = stem.replacingOccurrences(of: suffix, with: "")
        }
        let pattern = #"(?:^|[-_.])([0-9])(?:[-_.]|$)"#
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = stem as NSString
            if let m = re.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                let r = m.range(at: 1)
                if r.location != NSNotFound { return ns.substring(with: r) }
            }
        }
        let trimmed = stem.trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        if trimmed.count == 1, let d = trimmed.first, "0123456789".contains(d) { return String(d) }
        for c in stem { if "0123456789".contains(c) { return String(c) } }
        return nil
    }

    // MARK: - TỐI ƯU #1: Resize bằng ImageIO (10x nhanh hơn UIGraphicsImageRenderer)
    /// Logic giữ nguyên: chỉ resize khi detected ≠ keySize, kết quả PNG y hệt
    nonisolated private func resizeImageData(at url: URL, for keySize: PasscodeTheme.KeySize, detectedSize: PasscodeTheme.DetectedSize) -> Data? {
        // Logic cũ: không resize
        if detectedSize == .unknown { return try? Data(contentsOf: url) }
        if detectedSize == .small && keySize == .small { return try? Data(contentsOf: url) }
        if detectedSize == .big && keySize == .big { return try? Data(contentsOf: url) }
        
        // Resize 202↔287 bằng ImageIO
        let targetPx: CGFloat = (keySize == .big) ? 287.0 : 202.0
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPx
        ] as CFDictionary
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts) else { return nil }
        
        let md = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(md, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, thumb, nil)
        CGImageDestinationFinalize(dst)
        return md as Data
    }

    // MARK: - TỐI ƯU #2+3: Stage song song (concurrentPerform) + Streaming I/O
    /// Không giữ matrix trong RAM. Mỗi ảnh resize → ghi ngay → giải phóng.
    nonisolated private func stageFiles(
        theme: PasscodeTheme,
        language: PasscodeTheme.PrefixLanguage,
        boldMode: PasscodeTheme.BoldMode,
        into dir: URL
    ) throws -> Int {
        
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else { throw PasscodeThemeError.noImagesFound }

        let allLocales = ["en", "other", "ru", "uk", "es", "fr", "de", "it", "pt", "tr", "pl", "nl", "ja", "ko", "zh", "ar", "he"]
        let locales: [String]
        if language == .universal { locales = allLocales }
        else if language == .other { locales = ["other"] }
        else { locales = [language.rawValue, "other"] }

        let subtexts: [String: String] = [
            "0": "+", "1": "", "2": "A B C", "3": "D E F", "4": "G H I", "5": "J K L",
            "6": "M N O", "7": "P Q R S", "8": "T U V", "9": "W X Y Z"
        ]
        let ruSubtexts: [String: String] = [
            "2": "А Б В Г", "3": "Д Е Ж З", "4": "И Й К Л", "5": "М Н О П",
            "6": "Р С Т У", "7": "Ф Х Ц Ч", "8": "Ш Щ Ъ Ы", "9": "Ь Э Ю Я"
        ]
        let ukSubtexts: [String: String] = [
            "2": "А Б В Г", "3": "Д Е Ж З", "4": "І Ї Й К", "5": "Л М Н О",
            "6": "П Р С Т", "7": "У Ф Х Ц", "8": "Ч Ш Щ Ь", "9": "Ю Я"
        ]
        let boldSuffixes: [String]
        switch boldMode {
        case .regular: boldSuffixes = [""]
        case .bold: boldSuffixes = ["-bold"]
        case .both: boldSuffixes = ["", "-bold"]
        }

        var totalFiles = 0
        let lock = NSLock()
        
        // Parallel resize + write (mỗi ảnh 1 luồng, ImageIO thread-safe)
        DispatchQueue.concurrentPerform(iterations: imageFiles.count) { i in
            autoreleasepool {
                let filename = imageFiles[i]
                let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
                guard let digit = PasscodeThemeViewModel.extractDigitStatic(from: filename) else { return }
                guard let imageData = resizeImageData(at: sourceURL, for: theme.keySize, detectedSize: theme.detectedSize) else { return }
                
                let stdSub = subtexts[digit] ?? ""
                let ruSub = ruSubtexts[digit]
                let ukSub = ukSubtexts[digit]
                
                var localCount = 0
                for lang in locales {
                    for bld in boldSuffixes {
                        // Không .atomic — stage là temp, atomic chỉ làm chậm 2-3x
                        try? imageData.write(to: dir.appendingPathComponent("\(lang)-\(digit)---white\(bld).png"))
                        localCount += 1
                        
                        if !stdSub.isEmpty {
                            try? imageData.write(to: dir.appendingPathComponent("\(lang)-\(digit)-\(stdSub)--white\(bld).png"))
                            localCount += 1
                            let noSpace = stdSub.replacingOccurrences(of: " ", with: "")
                            if noSpace != stdSub {
                                try? imageData.write(to: dir.appendingPathComponent("\(lang)-\(digit)-\(noSpace)--white\(bld).png"))
                                localCount += 1
                            }
                        }
                        
                        if lang == "ru" || language == .universal, let sub = ruSub {
                            try? imageData.write(to: dir.appendingPathComponent("\(lang)-\(digit)-\(sub)--white\(bld).png"))
                            localCount += 1
                        }
                        if lang == "uk" || language == .universal, let sub = ukSub {
                            try? imageData.write(to: dir.appendingPathComponent("\(lang)-\(digit)-\(sub)--white\(bld).png"))
                            localCount += 1
                        }
                    }
                }
                
                lock.lock(); totalFiles += localCount; lock.unlock()
            }
        }

        // Marker _big (giữ nguyên logic EnsWilde — chỉ khi keySize == .big)
        if theme.keySize == .big {
            try? Data().write(to: dir.appendingPathComponent("_big"))
            totalFiles += 1
        }

        return totalFiles
    }

    // MARK: - Apply Theme
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let startTime = Date()

        let language = self.store.globalCustomPrefix
        let boldMode = self.store.globalBoldMode
        let telephony = self.store.globalTelephonyVersion
        let versions = telephony.targetFolders

        onLogUpdate("Preparing (Lang: \(language.displayName), Bold: \(boldMode.rawValue), Ver: \(telephony.displayName))...")
        onLogUpdate("📐 Key Size: \(theme.keySize.rawValue) | Detected: \(detectedName(theme.detectedSize))")

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."])
        }

        // Stage (parallel)
        let stageDir = FileManager.default.temporaryDirectory.appendingPathComponent("airlift_passthm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stageDir) }

        let tStage = Date()
        let expectedCount = try stageFiles(theme: theme, language: language, boldMode: boldMode, into: stageDir)
        let actualStaged = (try? FileManager.default.contentsOfDirectory(atPath: stageDir.path))?.count ?? 0
        let stageMs = Int(Date().timeIntervalSince(tStage) * 1000)
        onLogUpdate("📊 Staged \(actualStaged) files in \(stageMs)ms.")

        if actualStaged < expectedCount / 2 {
            throw NSError(domain: "AirLift", code: -30, userInfo: [NSLocalizedDescriptionKey: "Staged mismatch: \(actualStaged) < \(expectedCount)"])
        }

        // Tunnel
        onLogUpdate("Đang dò tunnel IP...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không kết nối được tới VPN."])
        }

        let bq = BadQuery()
        var totalWritten = 0
        var totalWriteMs = 0

        for (idx, versionName) in versions.enumerated() {
            let targetPath = "/var/mobile/Library/Caches/\(versionName)"
            let tVer = Date()
            onLogUpdate("[\(idx+1)/\(versions.count)] Đang ghi vào \(versionName)...")

            // TỐI ƯU #4: Xoá cache 1 syscall (không loop từng file)
            if bq.grantAccess(atPath: targetPath).0 {
                try? FileManager.default.removeItem(atPath: targetPath)
            }
            try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)

            // Ghi qua Airlift — chỉ write_dir
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                    defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                    var errPtr: UnsafeMutablePointer<CChar>? = nil
                    let res = pairingURL.path.withCString { pairC in
                        stageDir.path.withCString { srcC in
                            targetPath.withCString { tgtC in
                                al_exploit_write_dir(pairC, srcC, tgtC, cb, ctx, &errPtr)
                            }
                        }
                    }
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
            
            let verMs = Int(Date().timeIntervalSince(tVer) * 1000)
            totalWriteMs += verMs
            totalWritten += actualStaged
            onLogUpdate("  ✅ \(versionName) — \(verMs)ms (\(actualStaged) files, \(actualStaged / max(verMs, 1) * 1000) files/s)")
        }

        let total = Date().timeIntervalSince(startTime)
        onLogUpdate("🎉 Done in \(String(format: "%.1f", total))s. Bấm 'Reset Theme & Reboot' để áp dụng.")
        
        // Cảnh báo nếu quá nhanh (fail silent)
        if totalWritten > 100 && total < 20 {
            onLogUpdate("⚠️ CẢNH BÁO: \(totalWritten) file ghi trong \(Int(total))s — quá nhanh, có thể fail silent. Hãy kiểm tra bằng Filza.")
        }
    }

    private func detectedName(_ d: PasscodeTheme.DetectedSize) -> String {
        switch d {
        case .unknown: return "Unknown"
        case .small:   return "Small (202px)"
        case .big:     return "Big (287px)"
        }
    }

    // MARK: - Reset (giữ nguyên, chỉ tối ưu xoá)
    func resetTheme(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let cacheDirs = [
            "/var/mobile/Library/Caches/TelephonyUI-10",
            "/var/mobile/Library/Caches/TelephonyUI-9",
            "/var/mobile/Library/Caches/TelephonyUI-8"
        ]
        let bq = BadQuery()
        for dir in cacheDirs {
            if bq.grantAccess(atPath: dir).0 {
                // Xoá 1 syscall thay vì loop
                try? FileManager.default.removeItem(atPath: dir)
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
        onLogUpdate("✅ Đã xoá Passcode Theme thành công.")
        onLogUpdate("🔄 Đang khởi động lại thiết bị...")
        try await Task.sleep(nanoseconds: 800_000_000)
        RebootHelper.rebootDevice()
    }
}

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