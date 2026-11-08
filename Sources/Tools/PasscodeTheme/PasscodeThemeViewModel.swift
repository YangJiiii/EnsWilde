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

    // MARK: - Import (logic cũ EnsWilde)
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let result = try await Task.detached(priority: .userInitiated) {
            () -> (PasscodeTheme, PasscodeTheme.DetectedSize) in
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: temp) }
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: temp)
            let newTheme = PasscodeTheme(name: name)
            try? FileManager.default.createDirectory(at: newTheme.themeFolderURL, withIntermediateDirectories: true)
            let detectedSize = PasscodeThemeViewModel.detectSizeFromZIP(at: temp)
            do { try FileManager.default.unzipItem(at: temp, to: newTheme.themeFolderURL) }
            catch { try? FileManager.default.removeItem(at: newTheme.themeFolderURL); throw PasscodeThemeError.invalidFormat }
            try PasscodeThemeViewModel.extractImagesFromTelephonySubfolder(themeFolder: newTheme.themeFolderURL)
            return (newTheme, detectedSize)
        }.value
        var t = result.0
        t.detectedSize = result.1
        // KHÔNG auto-set keySize — user tự chọn trong ThemeDetailView
        self.store.addTheme(t)
    }

    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        try await importTheme(from: sourceURL, name: name)
    }

    // MARK: - Extract (logic cũ EnsWilde)

    nonisolated static private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for entry in archive {
                if entry.path.hasSuffix("_small") { return .small }
            }
            for entry in archive {
                if entry.path.hasSuffix("_big") { return .big }
            }
            return .unknown
        } catch { return .unknown }
    }

    /// Extract ảnh từ folder Telephony* ra root (giữ nguyên logic cũ)
    nonisolated static private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
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

    nonisolated static func extractDigitStatic(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "--white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "@2x", with: "")
            .replacingOccurrences(of: "@3x", with: "")
        if let re = try? NSRegularExpression(pattern: #"(?:^[a-zA-Z]+-)?([0-9*#])"#, options: .caseInsensitive) {
            let ns = stem as NSString
            if let m = re.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                let r = m.range(at: 1)
                if r.location != NSNotFound {
                    let d = ns.substring(with: r)
                    if "0123456789".contains(d) { return d }
                }
            }
        }
        for c in stem { if "0123456789".contains(c) { return String(c) } }
        return nil
    }

    // MARK: - Resize (logic EnsWilde cũ: 202↔287)

    /// - detected == .small && keySize == .big → x1.42
    /// - detected == .big && keySize == .small → x0.70
    /// - Cùng size hoặc unknown → không resize
    nonisolated private func resizeImageData(at url: URL, detected: PasscodeTheme.DetectedSize, target: PasscodeTheme.KeySize) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        // Không cần resize
        if detected == .unknown { return try? Data(contentsOf: url) }
        if detected == .small && target == .small { return try? Data(contentsOf: url) }
        if detected == .big && target == .big { return try? Data(contentsOf: url) }
        
        // Cần resize
        let maxPx: CGFloat = (target == .big) ? 287.0 : 202.0
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPx
        ] as CFDictionary
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts) else {
            return try? Data(contentsOf: url)
        }
        let md = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(md, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, thumb, nil)
        CGImageDestinationFinalize(dst)
        return md as Data
    }

    // MARK: - Stage (matrix AirCard + write thực)

    nonisolated private func stageFiles(theme: PasscodeTheme, language: PasscodeTheme.PrefixLanguage, boldMode: PasscodeTheme.BoldMode, into dir: URL) throws -> Int {
        let images = theme.getImageFiles()
        guard !images.isEmpty else { throw PasscodeThemeError.noImagesFound }

        let allLocales = ["en", "other", "ru", "uk", "es", "fr", "de", "it", "pt", "tr", "pl", "nl", "ja", "ko", "zh", "ar", "he"]
        let locales: [String] = (language == .universal) ? allLocales : (language == .other ? ["other"] : [language.rawValue, "other"])
        
        let subs: [String: String] = ["0": "+", "1": "", "2": "A B C", "3": "D E F", "4": "G H I", "5": "J K L", "6": "M N O", "7": "P Q R S", "8": "T U V", "9": "W X Y Z"]
        let ruSubs: [String: String] = ["2": "А Б В Г", "3": "Д Е Ж З", "4": "И Й К Л", "5": "М Н О П", "6": "Р С Т У", "7": "Ф Х Ц Ч", "8": "Ш Щ Ъ Ы", "9": "Ь Э Ю Я"]
        let ukSubs: [String: String] = ["2": "А Б В Г", "3": "Д Е Ж З", "4": "І Ї Й К", "5": "Л М Н О", "6": "П Р С Т", "7": "У Ф Х Ц", "8": "Ч Ш Щ Ь", "9": "Ю Я"]
        let boldSuffixes: [String] = (boldMode == .both) ? ["", "-bold"] : (boldMode == .bold ? ["-bold"] : [""])

        struct Encoded { let digit: String; let data: Data }
        var encoded: [Encoded] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: images.count) { i in
            let f = images[i]
            let u = theme.themeFolderURL.appendingPathComponent(f)
            guard let d = PasscodeThemeViewModel.extractDigitStatic(from: f),
                  let data = resizeImageData(at: u, detected: theme.detectedSize, target: theme.keySize) else { return }
            lock.lock(); encoded.append(Encoded(digit: d, data: data)); lock.unlock()
        }

        var count = 0
        for item in encoded {
            let d = item.digit
            let data = item.data
            let stdSub = subs[d] ?? ""
            let ruSub = ruSubs[d]
            let ukSub = ukSubs[d]

            for l in locales {
                for b in boldSuffixes {
                    try? data.write(to: dir.appendingPathComponent("\(l)-\(d)---white\(b).png"), options: .atomic); count += 1
                    if !stdSub.isEmpty {
                        try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(stdSub)--white\(b).png"), options: .atomic); count += 1
                        let ns = stdSub.replacingOccurrences(of: " ", with: "")
                        if ns != stdSub {
                            try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(ns)--white\(b).png"), options: .atomic); count += 1
                        }
                    }
                    if l == "ru" || language == .universal, let s = ruSub {
                        try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(s)--white\(b).png"), options: .atomic); count += 1
                    }
                    if l == "uk" || language == .universal, let s = ukSub {
                        try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(s)--white\(b).png"), options: .atomic); count += 1
                    }
                }
            }
        }

        // Big Key → tạo marker _big để iOS dùng layout big
        if theme.keySize == .big {
            try? Data().write(to: dir.appendingPathComponent("_big"))
            count += 1
        }
        return count
    }

    // MARK: - Airlift write
    nonisolated private func writeDir(pairingPath: String, srcDir: String, targetDir: String, onLogUpdate: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                var e: UnsafeMutablePointer<CChar>? = nil
                let r = pairingPath.withCString { p in srcDir.withCString { s in targetDir.withCString { t in al_exploit_write_dir(p, s, t, cb, ctx, &e) } } }
                if r != 0 {
                    let m = e != nil ? String(cString: e!) : "FFI error \(r)"
                    if let x = e { al_string_free(x) }
                    c.resume(throwing: NSError(domain: "AirLift", code: Int(r), userInfo: [NSLocalizedDescriptionKey: m]))
                } else {
                    if let x = e { al_string_free(x) }
                    c.resume()
                }
            }
        }
    }

    nonisolated private func injectFolder(pairingPath: String, srcDir: String, parentDir: String, name: String, onLogUpdate: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                var e: UnsafeMutablePointer<CChar>? = nil
                let r = pairingPath.withCString { p in srcDir.withCString { s in parentDir.withCString { pa in name.withCString { n in al_exploit_inject_folder(p, s, pa, n, cb, ctx, &e) } } } }
                if r != 0 {
                    let m = e != nil ? String(cString: e!) : "FFI error \(r)"
                    if let x = e { al_string_free(x) }
                    c.resume(throwing: NSError(domain: "AirLift", code: Int(r), userInfo: [NSLocalizedDescriptionKey: m]))
                } else {
                    if let x = e { al_string_free(x) }
                    c.resume()
                }
            }
        }
    }

    nonisolated private func verifyFile(pairingPath: String, iosPath: String) async -> Bool {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async {
                var data: UnsafeMutablePointer<UInt8>? = nil
                var len = 0
                var err: UnsafeMutablePointer<CChar>? = nil
                let r = pairingPath.withCString { p in iosPath.withCString { i in al_exploit_read_file(p, i, nil, nil, &data, &len, &err) } }
                if let p = data, len > 0 { al_bytes_free(p, len) }
                if let e = err { al_string_free(e) }
                c.resume(returning: r == 0 && len > 0)
            }
        }
    }

    // MARK: - Apply
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let start = Date()

        let language = self.store.globalCustomPrefix
        let boldMode = self.store.globalBoldMode
        // Chỉ dùng 1 version user chọn trong theme (không universal)
        let version = theme.telephonyVersion
        let targetFolder = version.rawValue

        onLogUpdate("Preparing (Lang: \(language.displayName), Bold: \(boldMode.rawValue), Ver: \(version.displayName))...")
        onLogUpdate("📐 Key Size: \(theme.keySize.rawValue) | Detected: \(detectedName(theme.detectedSize))")

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing pairing."])
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN not active."])
        }

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("passthm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }

        let tStage = Date()
        let count = try stageFiles(theme: theme, language: language, boldMode: boldMode, into: stage)
        guard count > 0 else { throw PasscodeThemeError.noImagesProcessed }

        let actual = (try? FileManager.default.contentsOfDirectory(atPath: stage.path))?.count ?? 0
        onLogUpdate("📊 Staged \(actual) files in \(Int(Date().timeIntervalSince(tStage)))s.")
        if actual < count / 2 {
            throw NSError(domain: "AirLift", code: -30, userInfo: [NSLocalizedDescriptionKey: "Staged mismatch: \(actual) < \(count)"])
        }

        onLogUpdate("Đang dò tunnel...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "No tunnel."])
        }

        let parent = "/var/mobile/Library/Caches"
        let target = "\(parent)/\(targetFolder)"
        let bq = BadQuery()

        if bq.grantAccess(atPath: target).0 {
            try? FileManager.default.removeItem(atPath: target)
        }

        let tWrite = Date()
        onLogUpdate("Ghi \(actual) file vào \(targetFolder)...")
        var done = false
        do {
            try await injectFolder(pairingPath: pairingURL.path, srcDir: stage.path, parentDir: parent, name: targetFolder, onLogUpdate: onLogUpdate)
            onLogUpdate("  ✅ inject_folder: \(Int(Date().timeIntervalSince(tWrite)))s")
            done = true
        } catch {
            onLogUpdate("  ⚠️ inject_folder fail: \(error.localizedDescription)")
        }
        if !done {
            try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
            try await writeDir(pairingPath: pairingURL.path, srcDir: stage.path, targetDir: target, onLogUpdate: onLogUpdate)
            onLogUpdate("  ✅ write_dir: \(Int(Date().timeIntervalSince(tWrite)))s")
        }

        // Verify
        let sample = (try? FileManager.default.contentsOfDirectory(atPath: stage.path))?.first ?? "en-1---white.png"
        let verifyPath = "\(target)/\(sample)"
        if await verifyFile(pairingPath: pairingURL.path, iosPath: verifyPath) {
            onLogUpdate("  🔍 Verify OK: \(sample)")
        } else {
            throw NSError(domain: "AirLift", code: -31, userInfo: [NSLocalizedDescriptionKey: "Verify failed: \(sample) not found on device."])
        }

        onLogUpdate("🎉 Done in \(Int(Date().timeIntervalSince(start)))s. Tap 'Reset Theme & Reboot' to apply.")
    }

    private func detectedName(_ d: PasscodeTheme.DetectedSize) -> String {
        switch d {
        case .unknown: return "Unknown"
        case .small: return "Small (202px)"
        case .big: return "Big (287px)"
        }
    }

    func resetTheme(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true; defer { isProcessing = false }
        let dirs = ["/var/mobile/Library/Caches/TelephonyUI-10", "/var/mobile/Library/Caches/TelephonyUI-9", "/var/mobile/Library/Caches/TelephonyUI-8"]
        let bq = BadQuery()
        for d in dirs {
            if bq.grantAccess(atPath: d).0 {
                try? FileManager.default.removeItem(atPath: d)
                try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
            }
        }
        onLogUpdate("✅ Cleared.")
        onLogUpdate("🔄 Rebooting...")
        try await Task.sleep(nanoseconds: 800_000_000)
        RebootHelper.rebootDevice()
    }
}

enum PasscodeThemeError: LocalizedError {
    case accessDenied, noImagesFound, noImagesProcessed, invalidFormat
    var errorDescription: String? {
        switch self {
        case .accessDenied:      return "Access denied."
        case .noImagesFound:     return "No images found."
        case .noImagesProcessed: return "Failed to process images."
        case .invalidFormat:     return "Invalid format."
        }
    }
}