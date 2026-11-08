import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

@MainActor
class PasscodeThemeViewModel: ObservableObject {

    @Published var isProcessing = false
    private var activeTaskID: UUID?
    private let store: PasscodeThemeStore

    init(store: PasscodeThemeStore) { self.store = store }

    // MARK: - Import (Y NGUYÊN)
    func importTheme(from sourceURL: URL, name: String) async throws {
        guard activeTaskID == nil else { return }
        let myID = UUID()
        activeTaskID = myID
        isProcessing = true
        defer {
            if activeTaskID == myID { activeTaskID = nil }
            isProcessing = false
        }
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

    // MARK: - detectSizeFromZIP (Y NGUYÊN)
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

    // MARK: - extractImagesRecursively (Y NGUYÊN)
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

    // MARK: - extractDigitStatic (Y NGUYÊN)
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

    // MARK: - processThemeFiles (Y NGUYÊN)
    nonisolated func processThemeFiles(
        theme: PasscodeTheme,
        language: PasscodeTheme.PrefixLanguage,
        boldMode: PasscodeTheme.BoldMode
    ) throws -> [(filename: String, imageData: Data)] {

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

        var processedFiles: [(String, Data)] = []
        var seenNames = Set<String>()
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: imageFiles.count) { i in
            autoreleasepool {
                let filename = imageFiles[i]
                let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
                guard let digit = PasscodeThemeViewModel.extractDigitStatic(from: filename) else { return }
                guard let image = UIImage(contentsOfFile: sourceURL.path) else { return }
                let processedImage = resizeImage(image, for: theme.keySize, detectedSize: theme.detectedSize)
                guard let imageData = processedImage.pngData() else { return }

                let stdSub = subtexts[digit] ?? ""
                let ruSub = ruSubtexts[digit]
                let ukSub = ukSubtexts[digit]

                var localFiles: [(String, Data)] = []
                for lang in locales {
                    for bld in boldSuffixes {
                        localFiles.append(("\(lang)-\(digit)---white\(bld).png", imageData))
                        if !stdSub.isEmpty {
                            localFiles.append(("\(lang)-\(digit)-\(stdSub)--white\(bld).png", imageData))
                            let noSpace = stdSub.replacingOccurrences(of: " ", with: "")
                            if noSpace != stdSub {
                                localFiles.append(("\(lang)-\(digit)-\(noSpace)--white\(bld).png", imageData))
                            }
                        }
                        if lang == "ru" || language == .universal, let sub = ruSub {
                            localFiles.append(("\(lang)-\(digit)-\(sub)--white\(bld).png", imageData))
                        }
                        if lang == "uk" || language == .universal, let sub = ukSub {
                            localFiles.append(("\(lang)-\(digit)-\(sub)--white\(bld).png", imageData))
                        }
                    }
                }
                lock.lock()
                for item in localFiles where !seenNames.contains(item.0) {
                    seenNames.insert(item.0)
                    processedFiles.append(item)
                }
                lock.unlock()
            }
        }
        return processedFiles
    }

    // MARK: - resizeImage (Y NGUYÊN)
    nonisolated private func resizeImage(_ image: UIImage, for keySize: PasscodeTheme.KeySize, detectedSize: PasscodeTheme.DetectedSize) -> UIImage {
        var sizeMultiplier: CGFloat = 1.0
        if detectedSize == .small && keySize == .big { sizeMultiplier = 287.0 / 202.0 }
        else if detectedSize == .big && keySize == .small { sizeMultiplier = 202.0 / 287.0 }
        else { return image }
        let currentSize = image.size
        guard currentSize.width > 0 && currentSize.height > 0 else { return image }
        let targetPixelSize = CGSize(width: currentSize.width * sizeMultiplier * image.scale, height: currentSize.height * sizeMultiplier * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetPixelSize)) }
    }

    // MARK: - writeDir (Y NGUYÊN)
    nonisolated private func writeDir(
        pairingPath: String,
        srcDir: String,
        targetDir: String,
        onLogUpdate: @escaping (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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

    // MARK: - VERIFY (mới — kiểm tra file thực sự có trên device)
    nonisolated private func verifyFileExists(pairingPath: String, remotePath: String) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .utility).async {
                var data: UnsafeMutablePointer<UInt8>? = nil
                var len = 0
                var err: UnsafeMutablePointer<CChar>? = nil
                let res = pairingPath.withCString { p in
                    remotePath.withCString { i in
                        al_exploit_read_file(p, i, nil, nil, &data, &len, &err)
                    }
                }
                if let d = data, len > 0 { al_bytes_free(d, len) }
                if let e = err { al_string_free(e) }
                c.resume(returning: res == 0 && len > 0)
            }
        }
    }

    // MARK: - Apply Theme (có verify + retry)
    func applyTheme(
        _ theme: PasscodeTheme,
        store: ToolStore,
        onLogUpdate: @escaping (String) -> Void
    ) async throws {
        guard activeTaskID == nil else { return }
        let myID = UUID()
        activeTaskID = myID
        isProcessing = true
        defer {
            if activeTaskID == myID { activeTaskID = nil }
            isProcessing = false
        }

        let startTime = Date()
        let language = self.store.globalCustomPrefix
        let boldMode = self.store.globalBoldMode
        let telephony = self.store.globalTelephonyVersion
        let versions = telephony.targetFolders
        let totalVersions = versions.count

        onLogUpdate("[1/6] Prepare: Lang=\(language.displayName), Bold=\(boldMode.rawValue), Ver=\(telephony.displayName)")
        if totalVersions > 1 {
            onLogUpdate("  Universal mode: ghi \(totalVersions) folder (không phải loop)")
        }

        let processedFiles = try processThemeFiles(theme: theme, language: language, boldMode: boldMode)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        onLogUpdate("[2/6] Matrix: \(processedFiles.count) x \(totalVersions) = \(processedFiles.count * totalVersions) file")

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."])
        }

        let stageThemeDir = FileManager.default.temporaryDirectory.appendingPathComponent("airlift_passthm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stageThemeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stageThemeDir) }

        let tStage = Date()
        DispatchQueue.concurrentPerform(iterations: processedFiles.count) { i in
            let (filename, data) = processedFiles[i]
            try? data.write(to: stageThemeDir.appendingPathComponent(filename))
        }
        try Data().write(to: stageThemeDir.appendingPathComponent("_big"))
        let stageMs = Int(Date().timeIntervalSince(tStage) * 1000)
        onLogUpdate("[3/6] Stage: \(processedFiles.count + 1) file trong \(stageMs)ms")

        onLogUpdate("[4/6] Dò tunnel...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không kết nối được tới VPN."])
        }
        onLogUpdate("[4/6] Tunnel OK")

        let bq = BadQuery()
        let pairPath = pairingURL.path
        let stagePath = stageThemeDir.path
        let fileCount = processedFiles.count
        let sampleFile = processedFiles.first!.0

        let tWrite = Date()
        for (idx, versionName) in versions.enumerated() {
            let targetPath = "/var/mobile/Library/Caches/\(versionName)"
            let tVer = Date()
            onLogUpdate("[5/6] Version \(idx+1)/\(totalVersions): \(versionName)")

            if bq.grantAccess(atPath: targetPath).0 {
                try? FileManager.default.removeItem(atPath: targetPath)
            }
            try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)

            // Retry tối đa 3 lần với verify sau mỗi lần
            var verified = false
            var lastError: Error?
            for attempt in 1...3 {
                do {
                    try await writeDir(
                        pairingPath: pairPath,
                        srcDir: stagePath,
                        targetDir: targetPath,
                        onLogUpdate: { _ in }
                    )
                    
                    // Verify 1 file mẫu trên device
                    let remotePath = "\(targetPath)/\(sampleFile)"
                    let ok = await verifyFileExists(pairingPath: pairPath, remotePath: remotePath)
                    if ok {
                        verified = true
                        break
                    } else {
                        onLogUpdate("  Attempt \(attempt): write OK nhưng verify FAIL, retry...")
                        // Xoá cache trước khi retry
                        if bq.grantAccess(atPath: targetPath).0 {
                            try? FileManager.default.removeItem(atPath: targetPath)
                        }
                        try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)
                    }
                } catch {
                    lastError = error
                    onLogUpdate("  Attempt \(attempt): error \(error.localizedDescription)")
                }
            }

            if !verified {
                throw NSError(
                    domain: "AirLift",
                    code: -40,
                    userInfo: [NSLocalizedDescriptionKey: "Ghi \(versionName) thất bại sau 3 lần. Lỗi cuối: \(lastError?.localizedDescription ?? "verify fail")"]
                )
            }

            let ms = Int(Date().timeIntervalSince(tVer) * 1000)
            let rate = ms > 0 ? (fileCount * 1000 / ms) : 0
            onLogUpdate("  -> \(versionName): \(ms)ms (\(rate) file/s) [verified]")
        }
        let writeMs = Int(Date().timeIntervalSince(tWrite) * 1000)

        let total = Int(Date().timeIntervalSince(startTime))
        onLogUpdate("[6/6] Done")
        onLogUpdate("  Files: \(fileCount * totalVersions)")
        onLogUpdate("  Write: \(writeMs)ms")
        onLogUpdate("  Total: \(total)s")
        onLogUpdate("Reset Theme & Reboot để áp dụng")
    }

    // MARK: - Reset (Y NGUYÊN)
    func resetTheme(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        guard activeTaskID == nil else { return }
        let myID = UUID()
        activeTaskID = myID
        isProcessing = true
        defer {
            if activeTaskID == myID { activeTaskID = nil }
            isProcessing = false
        }
        let cacheDirs = [
            "/var/mobile/Library/Caches/TelephonyUI-10",
            "/var/mobile/Library/Caches/TelephonyUI-9",
            "/var/mobile/Library/Caches/TelephonyUI-8"
        ]
        let bq = BadQuery()
        for dir in cacheDirs {
            if bq.grantAccess(atPath: dir).0 {
                try? FileManager.default.removeItem(atPath: dir)
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
        onLogUpdate("Đã xoá Passcode Theme")
        onLogUpdate("Đang khởi động lại...")
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