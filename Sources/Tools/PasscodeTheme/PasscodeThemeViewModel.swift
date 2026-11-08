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
        if result.1 == .big { themeWithSize.keySize = .big }
        self.store.addTheme(themeWithSize)
    }

    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        try await importTheme(from: sourceURL, name: name)
    }

    // MARK: - Helpers
    nonisolated static private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for entry in archive {
                let lower = entry.path.lowercased()
                if lower.hasSuffix("_big") || lower.contains("_big/") { return .big }
                if lower.hasSuffix("_small") || lower.contains("_small/") { return .small }
            }
            return .unknown
        } catch { return .unknown }
    }

    nonisolated static private func extractImagesRecursively(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: themeFolder.path) else { return }
        var movedDigits = Set<String>()
        var filesToMove: [(src: URL, destName: String)] = []

        while let rel = enumerator.nextObject() as? String {
            if rel.hasPrefix(".") || rel.contains("__MACOSX") { continue }
            let fullURL = themeFolder.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let ext = (rel as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            let filename = (rel as NSString).lastPathComponent
            guard let digit = extractDigitStatic(from: filename) else { continue }
            guard !movedDigits.contains(digit) else { continue }
            movedDigits.insert(digit)
            filesToMove.append((fullURL, "\(digit).png"))
        }

        for item in filesToMove {
            let destURL = themeFolder.appendingPathComponent(item.destName)
            try? fm.removeItem(at: destURL)
            try? fm.copyItem(at: item.src, to: destURL)
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

    nonisolated static func extractDigitStatic(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "--white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "@2x", with: "")
            .replacingOccurrences(of: "@3x", with: "")
        if let regex = try? NSRegularExpression(pattern: #"(?:^[a-zA-Z]+-)?([0-9*#])"#, options: .caseInsensitive) {
            let nsString = stem as NSString
            if let match = regex.firstMatch(in: stem, range: NSRange(location: 0, length: nsString.length)),
               match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                if range.location != NSNotFound {
                    let d = nsString.substring(with: range)
                    if "0123456789".contains(d) { return d }
                }
            }
        }
        for ch in stem { if "0123456789".contains(ch) { return String(ch) } }
        return nil
    }

    private func resolvedVersions(_ telephony: PasscodeTheme.TelephonyVersion) -> [String] {
        if telephony == .universal {
            let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            return major >= 18 ? ["TelephonyUI-10"] : (major >= 16 ? ["TelephonyUI-9"] : ["TelephonyUI-8"])
        }
        return telephony.targetFolders
    }

    // MARK: - Encode ảnh (ImageIO - nhanh gấp 10x)
    nonisolated private func fastResizeAndEncode(at url: URL, to targetSize: PasscodeTheme.KeySize, detected: PasscodeTheme.DetectedSize) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        let targetPx = (targetSize == .big) ? 287 : 202
        let maxPixelSize = CGFloat(targetPx)
        
        // Kiểm tra kích thước gốc - nếu đã đúng thì dùng luôn, chưa đúng thì resize
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let w = props[kCGImagePropertyPixelWidth as String] as? Int,
           let h = props[kCGImagePropertyPixelHeight as String] as? Int,
           w == targetPx && h == targetPx && detected != .unknown {
            return try? Data(contentsOf: url)
        }
        
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return try? Data(contentsOf: url)
        }
        
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumbnail, nil)
        CGImageDestinationFinalize(dest)
        return mutableData as Data
    }

    // MARK: - Stage (Hard Link + Parallel)
    nonisolated private func stageFiles(theme: PasscodeTheme, language: PasscodeTheme.PrefixLanguage, boldMode: PasscodeTheme.BoldMode, into stageDir: URL) throws -> Int {
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else { throw PasscodeThemeError.noImagesFound }

        let allLocales = ["en", "other", "ru", "uk", "es", "fr", "de", "it", "pt", "tr", "pl", "nl", "ja", "ko", "zh", "ar", "he"]
        let locales: [String] = (language == .universal) ? allLocales : (language == .other ? ["other"] : [language.rawValue, "other"])

        let subtexts: [String: String] = ["0": "+", "1": "", "2": "A B C", "3": "D E F", "4": "G H I", "5": "J K L", "6": "M N O", "7": "P Q R S", "8": "T U V", "9": "W X Y Z"]
        let ruSubtexts: [String: String] = ["2": "А Б В Г", "3": "Д Е Ж З", "4": "И Й К Л", "5": "М Н О П", "6": "Р С Т У", "7": "Ф Х Ц Ч", "8": "Ш Щ Ъ Ы", "9": "Ь Э Ю Я"]
        let ukSubtexts: [String: String] = ["2": "А Б В Г", "3": "Д Е Ж З", "4": "І Ї Й К", "5": "Л М Н О", "6": "П Р С Т", "7": "У Ф Х Ц", "8": "Ч Ш Щ Ь", "9": "Ю Я"]

        let boldSuffixes: [String] = (boldMode == .both) ? ["", "-bold"] : (boldMode == .bold ? ["-bold"] : [""])
        
        struct Task { let master: String; let data: Data; let links: [String] }
        var tasks: [Task] = []

        for filename in imageFiles {
            let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
            guard let digit = PasscodeThemeViewModel.extractDigitStatic(from: filename) else { continue }
            guard let imageData = fastResizeAndEncode(at: sourceURL, to: theme.keySize, detected: theme.detectedSize) else { continue }

            let stdSub = subtexts[digit] ?? ""
            let ruSub = ruSubtexts[digit]
            let ukSub = ukSubtexts[digit]
            
            var names: [String] = []
            for lang in locales {
                for bld in boldSuffixes {
                    names.append("\(lang)-\(digit)---white\(bld).png")
                    if !stdSub.isEmpty {
                        names.append("\(lang)-\(digit)-\(stdSub)--white\(bld).png")
                        let noSpace = stdSub.replacingOccurrences(of: " ", with: "")
                        if noSpace != stdSub {
                            names.append("\(lang)-\(digit)-\(noSpace)--white\(bld).png")
                        }
                    }
                    if lang == "ru" || language == .universal, let sub = ruSub {
                        names.append("\(lang)-\(digit)-\(sub)--white\(bld).png")
                    }
                    if lang == "uk" || language == .universal, let sub = ukSub {
                        names.append("\(lang)-\(digit)-\(sub)--white\(bld).png")
                    }
                }
            }
            guard let master = names.first else { continue }
            tasks.append(Task(master: master, data: imageData, links: Array(names.dropFirst())))
        }

        var total = 0
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: tasks.count) { i in
            let task = tasks[i]
            let masterURL = stageDir.appendingPathComponent(task.master)
            try? task.data.write(to: masterURL)
            for name in task.links {
                let destURL = stageDir.appendingPathComponent(name)
                do { try FileManager.default.linkItem(at: masterURL, to: destURL) }
                catch { try? FileManager.default.copyItem(at: masterURL, to: destURL) }
            }
            lock.lock(); total += 1 + task.links.count; lock.unlock()
        }
        
        try? Data().write(to: stageDir.appendingPathComponent("_big"))
        return total + 1
    }

    // MARK: - Ghi folder qua Airlift (3 phương thức, fallback tự động)

    /// Mode 1: inject_folder - 1 AirTraffic operation (nhanh nhất nếu hỗ trợ)
    nonisolated private func injectFolder(pairingPath: String, srcDir: String, parentDir: String, folderName: String, onLogUpdate: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = pairingPath.withCString { pairC in
                    srcDir.withCString { srcC in
                        parentDir.withCString { parentC in
                            folderName.withCString { destC in
                                al_exploit_inject_folder(pairC, srcC, parentC, destC, cb, ctx, &errPtr)
                            }
                        }
                    }
                }
                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "FFI error: \(res)"
                    if let e = errPtr { al_string_free(e) }
                    cont.resume(throwing: NSError(domain: "AirLift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    if let e = errPtr { al_string_free(e) }
                    cont.resume()
                }
            }
        }
    }

    /// Mode 2: write_dir (biết chạy chắc chắn)
    nonisolated private func writeDir(pairingPath: String, srcDir: String, targetDir: String, onLogUpdate: @escaping (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = pairingPath.withCString { pairC in
                    srcDir.withCString { srcC in
                        targetDir.withCString { tgtC in
                            al_exploit_write_dir(pairC, srcC, tgtC, cb, ctx, &errPtr)
                        }
                    }
                }
                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "FFI error: \(res)"
                    if let e = errPtr { al_string_free(e) }
                    cont.resume(throwing: NSError(domain: "AirLift", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg]))
                } else {
                    if let e = errPtr { al_string_free(e) }
                    cont.resume()
                }
            }
        }
    }

    /// Mode 3: parallel write_dir (2-3 tunnel đồng thời)
    nonisolated private func parallelWriteDir(pairingPath: String, stageDir: URL, targetDir: String, groups: Int, onLogUpdate: @escaping (String) -> Void) async throws {
        let allFiles = (try? FileManager.default.contentsOfDirectory(atPath: stageDir.path)) ?? []
        guard !allFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }

        // Round-robin split để cân bằng
        var buckets: [[String]] = Array(repeating: [], count: groups)
        for (i, f) in allFiles.enumerated() { buckets[i % groups].append(f) }

        // Tạo subdir với hard link
        var subdirs: [URL] = []
        for (i, files) in buckets.enumerated() where !files.isEmpty {
            let subdir = stageDir.appendingPathComponent("_p_\(i)")
            try? FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            for f in files {
                let src = stageDir.appendingPathComponent(f)
                let dst = subdir.appendingPathComponent(f)
                do { try FileManager.default.linkItem(at: src, to: dst) }
                catch { try? FileManager.default.copyItem(at: src, to: dst) }
            }
            subdirs.append(subdir)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for subdir in subdirs {
                let subPath = subdir.path
                group.addTask {
                    try await self.writeDir(pairingPath: pairingPath, srcDir: subPath, targetDir: targetDir, onLogUpdate: { _ in })
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Apply Theme (3 mode fallback: inject → parallel → sequential)
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let startTime = Date()

        let language = self.store.globalCustomPrefix
        let boldMode = self.store.globalBoldMode
        let telephony = self.store.globalTelephonyVersion
        let versions = resolvedVersions(telephony)

        onLogUpdate("Preparing (Lang: \(language.displayName), Bold: \(boldMode.rawValue), Ver: \(versions.joined(separator: ", ")))...")

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else { throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Pairing File."]) }
        guard NetworkStatus.isVPNTunnelPresent() else { throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN not active."]) }

        let stageDir = FileManager.default.temporaryDirectory.appendingPathComponent("airlift_passthm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stageDir) }

        let tStage = Date()
        let fileCount = try stageFiles(theme: theme, language: language, boldMode: boldMode, into: stageDir)
        guard fileCount > 0 else { throw PasscodeThemeError.noImagesProcessed }
        onLogUpdate("📊 Staged \(fileCount) files in \(Int(Date().timeIntervalSince(tStage)))s.")

        onLogUpdate("Đang dò tunnel IP...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not connect to VPN."])
        }

        let targetParent = "/var/mobile/Library/Caches"
        let bq = BadQuery()

        for (idx, versionName) in versions.enumerated() {
            let targetPath = "\(targetParent)/\(versionName)"
            let tVer = Date()
            onLogUpdate("[\(idx+1)/\(versions.count)] \(versionName)...")

            // Clear cache trước (1 syscall)
            if bq.grantAccess(atPath: targetPath).0 {
                try? FileManager.default.removeItem(atPath: targetPath)
            }

            // Try 1: inject_folder (nhanh nhất)
            var done = false
            do {
                try await injectFolder(pairingPath: pairingURL.path, srcDir: stageDir.path, parentDir: targetParent, folderName: versionName, onLogUpdate: onLogUpdate)
                onLogUpdate("  ✅ inject_folder: \(Int(Date().timeIntervalSince(tVer)))s")
                done = true
            } catch {
                onLogUpdate("  ⚠️ inject_folder failed: \(error.localizedDescription)")
            }

            // Try 2: parallel write_dir
            if !done {
                try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)
                let groups = max(2, min(3, ProcessInfo.processInfo.activeProcessorCount / 2))
                do {
                    try await parallelWriteDir(pairingPath: pairingURL.path, stageDir: stageDir, targetDir: targetPath, groups: groups, onLogUpdate: onLogUpdate)
                    onLogUpdate("  ✅ parallel write_dir (\(groups)x): \(Int(Date().timeIntervalSince(tVer)))s")
                    done = true
                } catch {
                    onLogUpdate("  ⚠️ parallel failed: \(error.localizedDescription)")
                    try? FileManager.default.removeItem(atPath: targetPath)
                    try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)
                }
            }

            // Try 3: sequential write_dir (last resort)
            if !done {
                try await writeDir(pairingPath: pairingURL.path, srcDir: stageDir.path, targetDir: targetPath, onLogUpdate: onLogUpdate)
                onLogUpdate("  ✅ sequential write_dir: \(Int(Date().timeIntervalSince(tVer)))s")
            }
        }

        let total = Int(Date().timeIntervalSince(startTime))
        onLogUpdate("🎉 Done in \(total)s. Tap 'Reset Theme & Reboot' to apply.")
    }

    // MARK: - Reset
    func resetTheme(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }
        let cacheDirs = ["/var/mobile/Library/Caches/TelephonyUI-10", "/var/mobile/Library/Caches/TelephonyUI-9", "/var/mobile/Library/Caches/TelephonyUI-8"]
        let bq = BadQuery()
        for dir in cacheDirs {
            if bq.grantAccess(atPath: dir).0 {
                try? FileManager.default.removeItem(atPath: dir)
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
        onLogUpdate("✅ Cleared Passcode Theme.")
        onLogUpdate("🔄 Rebooting device...")
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
        case .invalidFormat:     return "Invalid theme format."
        }
    }
}