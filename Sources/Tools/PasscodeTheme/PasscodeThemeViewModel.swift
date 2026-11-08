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

    // MARK: - Import
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let result = try await Task.detached(priority: .userInitiated) {
            () -> (PasscodeTheme, PasscodeTheme.DetectedSize) in
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: temp) }
            let data = try Data(contentsOf: sourceURL); try data.write(to: temp)
            let newTheme = PasscodeTheme(name: name)
            try? FileManager.default.createDirectory(at: newTheme.themeFolderURL, withIntermediateDirectories: true)
            let detectedSize = PasscodeThemeViewModel.detectSizeFromZIP(at: temp)
            do { try FileManager.default.unzipItem(at: temp, to: newTheme.themeFolderURL) }
            catch { try? FileManager.default.removeItem(at: newTheme.themeFolderURL); throw PasscodeThemeError.invalidFormat }
            try PasscodeThemeViewModel.extractImagesRecursively(themeFolder: newTheme.themeFolderURL)
            return (newTheme, detectedSize)
        }.value
        var t = result.0
        t.detectedSize = result.1
        // KHÔNG auto-set keySize — user tự chọn trong Theme Detail
        self.store.addTheme(t)
    }

    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        try await importTheme(from: sourceURL, name: name)
    }

    // MARK: - Helpers
    nonisolated static private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for e in archive {
                let l = e.path.lowercased()
                if l.hasSuffix("_big") || l.contains("_big/") { return .big }
                if l.hasSuffix("_small") || l.contains("_small/") { return .small }
            }
            return .unknown
        } catch { return .unknown }
    }

    nonisolated static private func extractImagesRecursively(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: themeFolder.path) else { return }
        var moved = Set<String>()
        var list: [(URL, String)] = []
        while let rel = e.nextObject() as? String {
            if rel.hasPrefix(".") || rel.contains("__MACOSX") { continue }
            let url = themeFolder.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let ext = (rel as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            let filename = (rel as NSString).lastPathComponent
            guard let d = extractDigitStatic(from: filename), !moved.contains(d) else { continue }
            moved.insert(d)
            list.append((url, "\(d).png"))
        }
        for (src, name) in list {
            let dst = themeFolder.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        }
        if let c = try? fm.contentsOfDirectory(atPath: themeFolder.path) {
            for i in c {
                let u = themeFolder.appendingPathComponent(i)
                var d: ObjCBool = false
                if fm.fileExists(atPath: u.path, isDirectory: &d), d.boolValue {
                    try? fm.removeItem(at: u)
                }
            }
        }
    }

    nonisolated static func extractDigitStatic(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "--white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "@2x", with: "").replacingOccurrences(of: "@3x", with: "")
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

    private func resolvedVersions(_ t: PasscodeTheme.TelephonyVersion) -> [String] {
        if t == .universal {
            let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            return major >= 18 ? ["TelephonyUI-10"] : (major >= 16 ? ["TelephonyUI-9"] : ["TelephonyUI-8"])
        }
        return t.targetFolders
    }

    // MARK: - Encode (ImageIO + resize theo EnsWilde cũ)

    /// Resize theo logic EnsWilde cũ:
    /// - detected == unknown → giữ nguyên
    /// - detected == target → giữ nguyên
    /// - detected ≠ target → resize (202↔287)
    nonisolated private func fastEncode(at url: URL, detected: PasscodeTheme.DetectedSize, target: PasscodeTheme.KeySize) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        // Case 1: Unknown detected size → không resize
        if detected == .unknown { return try? Data(contentsOf: url) }
        
        // Case 2: Detected == target → không resize
        if (detected == .big && target == .big) || (detected == .small && target == .small) {
            return try? Data(contentsOf: url)
        }
        
        // Case 3: Detected ≠ target → resize
        let px: CGFloat = (target == .big) ? 287 : 202
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: px
        ] as CFDictionary
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else {
            return try? Data(contentsOf: url)
        }
        let md = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(md, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, thumb, nil)
        CGImageDestinationFinalize(dst)
        return md as Data
    }

    // MARK: - Stage (ghi thực, không hard link)
    nonisolated private func stageFiles(theme: PasscodeTheme, language: PasscodeTheme.PrefixLanguage, boldMode: PasscodeTheme.BoldMode, into dir: URL) throws -> Int {
        let images = theme.getImageFiles()
        guard !images.isEmpty else { throw PasscodeThemeError.noImagesFound }
        
        let allLocales = ["en", "other", "ru", "uk", "es", "fr", "de", "it", "pt", "tr", "pl", "nl", "ja", "ko", "zh", "ar", "he"]
        let locales: [String] = (language == .universal) ? allLocales : (language == .other ? ["other"] : [language.rawValue, "other"])
        
        let subs: [String: String] = ["0": "+", "1": "", "2": "A B C", "3": "D E F", "4": "G H I", "5": "J K L", "6": "M N O", "7": "P Q R S", "8": "T U V", "9": "W X Y Z"]
        let ruSubs: [String: String] = ["2": "А Б В Г", "3": "Д Е Ж З", "4": "И Й К Л", "5": "М Н О П", "6": "Р С Т У", "7": "Ф Х Ц Ч", "8": "Ш Щ Ъ Ы", "9": "Ь Э Ю Я"]
        let ukSubs: [String: String] = ["2": "А Б В Г", "3": "Д Е Ж З", "4": "І Ї Й К", "5": "Л М Н О", "6": "П Р С Т", "7": "У Ф Х Ц", "8": "Ч Ш Щ Ь", "9": "Ю Я"]
        let bold: [String] = (boldMode == .both) ? ["", "-bold"] : (boldMode == .bold ? ["-bold"] : [""])
        
        // Encode song song (ImageIO thread-safe)
        struct Encoded { let digit: String; let data: Data }
        var encoded: [Encoded] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: images.count) { i in
            let f = images[i]
            let u = theme.themeFolderURL.appendingPathComponent(f)
            guard let d = PasscodeThemeViewModel.extractDigitStatic(from: f),
                  let data = fastEncode(at: u, detected: theme.detectedSize, target: theme.keySize) else { return }
            lock.lock(); encoded.append(Encoded(digit: d, data: data)); lock.unlock()
        }
        
        // Ghi từng file thực
        var count = 0
        for item in encoded {
            let d = item.digit
            let data = item.data
            let stdSub = subs[d] ?? ""
            let ruSub = ruSubs[d]
            let ukSub = ukSubs[d]
            
            for l in locales {
                for b in bold {
                    // 1. Không subtext
                    try? data.write(to: dir.appendingPathComponent("\(l)-\(d)---white\(b).png"), options: .atomic)
                    count += 1
                    
                    // 2. Subtext Latin
                    if !stdSub.isEmpty {
                        try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(stdSub)--white\(b).png"), options: .atomic)
                        count += 1
                        let noSpace = stdSub.replacingOccurrences(of: " ", with: "")
                        if noSpace != stdSub {
                            try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(noSpace)--white\(b).png"), options: .atomic)
                            count += 1
                        }
                    }
                    // 3. Nga
                    if l == "ru" || language == .universal, let s = ruSub {
                        try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(s)--white\(b).png"), options: .atomic)
                        count += 1
                    }
                    // 4. Ukraina
                    if l == "uk" || language == .universal, let s = ukSub {
                        try? data.write(to: dir.appendingPathComponent("\(l)-\(d)-\(s)--white\(b).png"), options: .atomic)
                        count += 1
                    }
                }
            }
        }
        
        // Marker _big: CHỈ tạo khi keySize == .big
        // Cách này giúp iOS dùng layout big (phím sát nhau → liền mạch)
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

        let lang = self.store.globalCustomPrefix
        let boldMode = self.store.globalBoldMode
        let telephony = self.store.globalTelephonyVersion
        let versions = resolvedVersions(telephony)

        onLogUpdate("Preparing (Lang: \(lang.displayName), Bold: \(boldMode.rawValue), Ver: \(versions.joined(separator: ",")))...")
        onLogUpdate("📐 Key Size: \(theme.keySize.rawValue) | Detected: \(theme.detectedSize)")
        
        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else { throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing pairing."]) }
        guard NetworkStatus.isVPNTunnelPresent() else { throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN not active."]) }

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("passthm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }

        let tStage = Date()
        let count = try stageFiles(theme: theme, language: lang, boldMode: boldMode, into: stage)
        guard count > 0 else { throw PasscodeThemeError.noImagesProcessed }
        
        let actualStaged = (try? FileManager.default.contentsOfDirectory(atPath: stage.path))?.count ?? 0
        onLogUpdate("📊 Staged \(actualStaged) files in \(Int(Date().timeIntervalSince(tStage)))s (expected: \(count)).")
        
        if actualStaged < count / 2 {
            throw NSError(domain: "AirLift", code: -30, userInfo: [NSLocalizedDescriptionKey: "Staged mismatch: \(actualStaged) < \(count)"])
        }

        onLogUpdate("Đang dò tunnel...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "No tunnel."])
        }

        let parent = "/var/mobile/Library/Caches"
        let bq = BadQuery()

        for (idx, v) in versions.enumerated() {
            let target = "\(parent)/\(v)"
            let tVer = Date()
            onLogUpdate("[\(idx+1)/\(versions.count)] \(v)...")

            if bq.grantAccess(atPath: target).0 {
                try? FileManager.default.removeItem(atPath: target)
            }

            var mode = "inject_folder"
            var done = false
            do {
                try await injectFolder(pairingPath: pairingURL.path, srcDir: stage.path, parentDir: parent, name: v, onLogUpdate: onLogUpdate)
                onLogUpdate("  ✅ inject_folder: \(Int(Date().timeIntervalSince(tVer)))s")
                done = true
            } catch {
                onLogUpdate("  ⚠️ inject_folder fail: \(error.localizedDescription)")
            }

            if !done {
                mode = "write_dir"
                try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
                try await writeDir(pairingPath: pairingURL.path, srcDir: stage.path, targetDir: target, onLogUpdate: onLogUpdate)
                onLogUpdate("  ✅ write_dir: \(Int(Date().timeIntervalSince(tVer)))s")
            }

            // Verify
            let sample = (try? FileManager.default.contentsOfDirectory(atPath: stage.path))?.first ?? "en-1---white.png"
            let verifyPath = "\(target)/\(sample)"
            let ok = await verifyFile(pairingPath: pairingURL.path, iosPath: verifyPath)
            if ok {
                onLogUpdate("  🔍 Verify OK: \(sample) (\(mode))")
            } else {
                throw NSError(domain: "AirLift", code: -31, userInfo: [NSLocalizedDescriptionKey: "Verify failed: \(sample) not found on device."])
            }
        }
        onLogUpdate("🎉 Done in \(Int(Date().timeIntervalSince(start)))s. Tap 'Reset Theme & Reboot' to apply.")
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