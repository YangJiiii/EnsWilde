//
//  PasscodeThemeViewModel.swift
//  EnsWilde
//
//  Đã chuyển từ BadQuery → WorseQuery.
//  Yêu cầu: Các file WorseQueryHelper.swift, WorseQueryWrapper.swift,
//  WorseQueryManager.swift, worse_query.h, worse_query.m phải có trong
//  Build Phases → Compile Sources của target EnsWilde.
//

import Foundation
import SwiftUI
import UIKit
import ZIPFoundation
import AirliftFFI
import Network

// MARK: - Preset tốc độ
enum SpeedPreset: String, CaseIterable {
    case safe       // ~14.8s — verify cả 3 version, reboot 800ms
    case balanced   // ~13.8s — verify version cuối, reboot 500ms
    case fast       // ~13.2s — verify cuối, reboot 400ms (DEFAULT)
    case turbo      // ~12.6s — không verify, reboot 300ms
    case ferrari    // ~12.0s — không verify, reboot 200ms, log im lặng, retry 1

    var displayName: String {
        switch self {
        case .safe:     return "Safe"
        case .balanced: return "Balanced"
        case .fast:     return "Fast (default)"
        case .turbo:    return "Turbo"
        case .ferrari:  return "Ferrari 🏎"
        }
    }

    var description: String {
        switch self {
        case .safe:     return "Verify cả 3 version, reboot 800ms. An toàn tối đa."
        case .balanced: return "Verify version cuối, reboot 500ms."
        case .fast:     return "Verify version cuối, reboot 400ms. Cân bằng."
        case .turbo:    return "Không verify, reboot 300ms. Nhanh hơn ~600ms."
        case .ferrari:  return "Không verify, reboot 200ms, retry 1. Nhanh nhất có thể."
        }
    }

    // (verify, verifyAll, rebootMs, retries, logLevel)
    var config: (verify: Bool, verifyAll: Bool, rebootMs: Int, retries: Int, logLevel: LogLevel) {
        switch self {
        case .safe:     return (true,  true,  800, 3, .normal)
        case .balanced: return (true,  false, 500, 3, .normal)
        case .fast:     return (true,  false, 400, 3, .normal)
        case .turbo:    return (false, false, 300, 2, .normal)
        case .ferrari:  return (false, false, 200, 1, .silent)
        }
    }
}

enum LogLevel: Int {
    case silent  = 0
    case normal  = 1
    case verbose = 2
}

// MARK: - Counter an toàn luồng
private final class WriteCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}

@MainActor
class PasscodeThemeViewModel: ObservableObject {

    @Published var isProcessing = false
    private var activeTaskID: UUID?
    private let store: PasscodeThemeStore

    // MARK: - 🎛 KNOBS
    var speedPreset: SpeedPreset = .fast {
        didSet { applyPreset(speedPreset) }
    }
    var verifyAfterWrite: Bool = true
    var verifyAllVersions: Bool = false
    var rebootDelayMs: Int = 400
    var retryAttempts: Int = 3
    var logLevel: LogLevel = .normal

    // MARK: - Init
    init(store: PasscodeThemeStore) {
        self.store = store
        applyPreset(.fast)
    }

    private func applyPreset(_ preset: SpeedPreset) {
        let c = preset.config
        verifyAfterWrite = c.verify
        verifyAllVersions = c.verifyAll
        rebootDelayMs = c.rebootMs
        retryAttempts = c.retries
        logLevel = c.logLevel
    }

    // MARK: - Ước lượng thời gian
    func estimateDurationSec(language: PasscodeTheme.PrefixLanguage,
                             telephony: PasscodeTheme.TelephonyVersion) -> Double {
        let localeMultiplier: Double = {
            switch language {
            case .universal: return 16.0
            case .other:     return 1.0
            default:         return 2.0
            }
        }()
        let estFilesPerVersion = 10.0 * localeMultiplier
        let versionCount = Double(telephony.targetFolders.count)
        let totalFiles = estFilesPerVersion * versionCount
        let writeSec = totalFiles * 0.007
        let overhead = 0.5 + versionCount * 0.05
        return writeSec + overhead + Double(rebootDelayMs) / 1000
    }

    // MARK: - Loại file
    nonisolated static func isSupportedPasscodeThemeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["zip", "passthm", "3105pass"].contains(ext)
    }

    nonisolated static func describeFileType(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "passthm": return "Passcode Theme (.passthm)"
        case "3105pass": return "Legacy Theme (.3105pass)"
        case "zip": return "ZIP Archive (.zip)"
        default: return "Unknown (.\(url.pathExtension))"
        }
    }

    // MARK: - Import ⚡ copyItem trực tiếp
    func importTheme(from sourceURL: URL, name: String) async throws {
        guard activeTaskID == nil else { return }
        let myID = UUID()
        activeTaskID = myID
        isProcessing = true
        defer {
            if activeTaskID == myID { activeTaskID = nil }
            isProcessing = false
        }

        guard PasscodeThemeViewModel.isSupportedPasscodeThemeFile(sourceURL) else {
            throw PasscodeThemeError.invalidFormat
        }

        let result = try await Task.detached(priority: .userInitiated) {
            () -> (PasscodeTheme, PasscodeTheme.DetectedSize) in
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: tempFileURL) }

            try? FileManager.default.removeItem(at: tempFileURL)
            try FileManager.default.copyItem(at: sourceURL, to: tempFileURL)

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

    // MARK: - detectSizeFromZIP
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

    // MARK: - extractImagesRecursively
    nonisolated static func extractImagesRecursively(themeFolder: URL) throws {
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
            if (try? fm.moveItem(at: item.src, to: destURL)) == nil {
                try? fm.copyItem(at: item.src, to: destURL)
            }
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

    // MARK: - Regex static
    nonisolated private static let digitRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?:^[a-zA-Z]+-)?([0-9*#])"#, options: .caseInsensitive)
    }()

    nonisolated static func extractDigitStatic(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "--white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "@2x", with: "")
            .replacingOccurrences(of: "@3x", with: "")
        if let regex = Self.digitRegex {
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

    nonisolated private static func extractVersionNumber(_ name: String) -> Int {
        if let last = name.split(separator: "-").last, let n = Int(last) { return n }
        return 0
    }

    // MARK: - processThemeFiles
    nonisolated func processThemeFiles(
        theme: PasscodeTheme,
        language: PasscodeTheme.PrefixLanguage,
        boldMode: PasscodeTheme.BoldMode
    ) throws -> [(filename: String, sourceURL: URL, digit: String, needsResize: Bool)] {

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

        let needsResize = (theme.detectedSize == .small && theme.keySize == .big) ||
                          (theme.detectedSize == .big && theme.keySize == .small)
        let folderURL = theme.themeFolderURL

        var processedFiles: [(String, URL, String, Bool)] = []
        var seenNames = Set<String>()
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: imageFiles.count) { i in
            autoreleasepool {
                let filename = imageFiles[i]
                let sourceURL = folderURL.appendingPathComponent(filename)
                guard let digit = PasscodeThemeViewModel.extractDigitStatic(from: filename) else { return }

                let stdSub = subtexts[digit] ?? ""
                let ruSub = ruSubtexts[digit]
                let ukSub = ukSubtexts[digit]

                var localNames: [String] = []
                localNames.reserveCapacity(locales.count * boldSuffixes.count * 5)
                for lang in locales {
                    for bld in boldSuffixes {
                        localNames.append("\(lang)-\(digit)---white\(bld).png")
                        if !stdSub.isEmpty {
                            localNames.append("\(lang)-\(digit)-\(stdSub)--white\(bld).png")
                            let noSpace = stdSub.replacingOccurrences(of: " ", with: "")
                            if noSpace != stdSub {
                                localNames.append("\(lang)-\(digit)-\(noSpace)--white\(bld).png")
                            }
                        }
                        if lang == "ru" || language == .universal, let sub = ruSub {
                            localNames.append("\(lang)-\(digit)-\(sub)--white\(bld).png")
                        }
                        if lang == "uk" || language == .universal, let sub = ukSub {
                            localNames.append("\(lang)-\(digit)-\(sub)--white\(bld).png")
                        }
                    }
                }
                lock.lock()
                for name in localNames where !seenNames.contains(name) {
                    seenNames.insert(name)
                    processedFiles.append((name, sourceURL, digit, needsResize))
                }
                lock.unlock()
            }
        }
        return processedFiles
    }

    // MARK: - resizeImage
    nonisolated static private func resizeImage(
        _ image: UIImage,
        for keySize: PasscodeTheme.KeySize,
        detectedSize: PasscodeTheme.DetectedSize
    ) -> UIImage {
        var sizeMultiplier: CGFloat = 1.0
        if detectedSize == .small && keySize == .big { sizeMultiplier = 287.0 / 202.0 }
        else if detectedSize == .big && keySize == .small { sizeMultiplier = 202.0 / 287.0 }
        else { return image }
        let currentSize = image.size
        guard currentSize.width > 0 && currentSize.height > 0 else { return image }
        let targetPixelSize = CGSize(
            width: currentSize.width * sizeMultiplier * image.scale,
            height: currentSize.height * sizeMultiplier * image.scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetPixelSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetPixelSize)) }
    }

    // MARK: - writeDir FFI
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

    // MARK: - verifyFileExists FFI
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

    // MARK: - fastStage
    nonisolated private func fastStage(
        processedFiles: [(filename: String, sourceURL: URL, digit: String, needsResize: Bool)],
        theme: PasscodeTheme,
        stageDir: URL
    ) throws -> Int {
        let fm = FileManager.default
        let n = processedFiles.count
        guard n > 0 else { return 0 }

        fm.createFile(atPath: stageDir.appendingPathComponent("_big").path, contents: nil)

        var primaryIndices: [Int] = []
        primaryIndices.reserveCapacity(16)
        var primaryURLByDigit: [String: URL] = [:]
        primaryURLByDigit.reserveCapacity(16)
        var nonPrimaryIndices: [Int] = []
        nonPrimaryIndices.reserveCapacity(n)

        for i in 0..<n {
            let p = processedFiles[i]
            if primaryURLByDigit[p.digit] == nil {
                primaryIndices.append(i)
                primaryURLByDigit[p.digit] = stageDir.appendingPathComponent(p.filename)
            } else {
                nonPrimaryIndices.append(i)
            }
        }

        DispatchQueue.concurrentPerform(iterations: primaryIndices.count) { idx in
            autoreleasepool {
                let p = processedFiles[primaryIndices[idx]]
                guard let dest = primaryURLByDigit[p.digit] else { return }
                if p.needsResize {
                    guard let image = UIImage(contentsOfFile: p.sourceURL.path) else { return }
                    let processed = PasscodeThemeViewModel.resizeImage(
                        image,
                        for: theme.keySize,
                        detectedSize: theme.detectedSize
                    )
                    guard let data = processed.pngData() else { return }
                    try? data.write(to: dest)
                } else {
                    if (try? fm.linkItem(at: p.sourceURL, to: dest)) == nil {
                        try? fm.copyItem(at: p.sourceURL, to: dest)
                    }
                }
            }
        }

        DispatchQueue.concurrentPerform(iterations: nonPrimaryIndices.count) { idx in
            autoreleasepool {
                let p = processedFiles[nonPrimaryIndices[idx]]
                guard let src = primaryURLByDigit[p.digit] else { return }
                let dest = stageDir.appendingPathComponent(p.filename)
                if (try? fm.linkItem(at: src, to: dest)) == nil {
                    try? fm.copyItem(at: src, to: dest)
                }
            }
        }

        return n + 1
    }

    // MARK: - writeOneVersion ⚡ (WorseQuery)
    nonisolated private func writeOneVersion(
        versionName: String,
        targetPath: String,
        stagePath: String,
        pairPath: String,
        sampleFile: String,
        totalPerVersion: Int,
        shouldVerify: Bool,
        bq: WorseQuery,                         // ← Đã đổi từ BadQuery → WorseQuery
        onLogUpdate: @escaping (String) -> Void
    ) async throws {
        if bq.grantAccess(atPath: targetPath).0 {
            try? FileManager.default.removeItem(atPath: targetPath)
        }
        try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)

        let logBatch: Int = {
            switch logLevel {
            case .silent:  return 999_999
            case .normal:  return 200
            case .verbose: return 1
            }
        }()

        let maxAttempts = max(1, min(3, retryAttempts))
        var lastError: Error?
        for attempt in 1...maxAttempts {
            let counter = WriteCounter()
            do {
                try await writeDir(
                    pairingPath: pairPath,
                    srcDir: stagePath,
                    targetDir: targetPath,
                    onLogUpdate: { line in
                        let current = counter.increment()
                        guard current % logBatch == 0 || current == totalPerVersion else { return }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let body = trimmed.lowercased().hasPrefix("write") ? trimmed : "write file \(trimmed)"
                        let msg = "  \(current)/\(totalPerVersion): \(body)"
                        DispatchQueue.main.async { onLogUpdate(msg) }
                    }
                )

                guard shouldVerify else { return }

                let ok = await verifyFileExists(pairingPath: pairPath, remotePath: "\(targetPath)/\(sampleFile)")
                if ok { return }

                onLogUpdate("  ⚠️ Attempt \(attempt)/\(maxAttempts) verify FAIL, retry...")
                if bq.grantAccess(atPath: targetPath).0 {
                    try? FileManager.default.removeItem(atPath: targetPath)
                }
                try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)
            } catch {
                lastError = error
                onLogUpdate("  ⚠️ Attempt \(attempt)/\(maxAttempts) error: \(error.localizedDescription)")
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
        throw NSError(
            domain: "AirLift",
            code: -40,
            userInfo: [NSLocalizedDescriptionKey: "Ghi \(versionName) thất bại sau \(maxAttempts) lần. Lỗi cuối: \(lastError?.localizedDescription ?? "verify fail")"]
        )
    }

    // MARK: - Apply Theme
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

        var seenVersions = Set<String>()
        let rawVersions = telephony.targetFolders
        let versions = rawVersions
            .filter { seenVersions.insert($0).inserted }
            .sorted {
                PasscodeThemeViewModel.extractVersionNumber($0) < PasscodeThemeViewModel.extractVersionNumber($1)
            }
        let totalVersions = versions.count

        onLogUpdate("[1/6] Prepare: Lang=\(language.displayName), Bold=\(boldMode.rawValue), Ver=\(telephony.displayName)")
        onLogUpdate("  → Preset: \(speedPreset.displayName) · verify=\(verifyAfterWrite ? (verifyAllVersions ? "all" : "last") : "off") · reboot=\(rebootDelayMs)ms · retry=\(retryAttempts)")
        onLogUpdate("  → Sẽ ghi \(totalVersions) folder: \(versions.joined(separator: " → "))")

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."])
        }

        // Tunnel detect song song
        onLogUpdate("[3/6] Dò tunnel (song song với process)...")
        let logCb = onLogUpdate
        let tunnelTask = Task.detached(priority: .userInitiated) {
            await AirliftHostResolver.bestAvailable(log: logCb) != nil
        }
        defer { tunnelTask.cancel() }

        let tProcess = Date()
        let processedFiles = try processThemeFiles(theme: theme, language: language, boldMode: boldMode)
        let processMs = Int(Date().timeIntervalSince(tProcess) * 1000)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }

        let stageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("airlift_passthm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stageDir) }

        let tStage = Date()
        let totalPerVersion = try fastStage(processedFiles: processedFiles, theme: theme, stageDir: stageDir)
        let stageMs = Int(Date().timeIntervalSince(tStage) * 1000)

        onLogUpdate("[2/6] Matrix: \(totalPerVersion) file/version × \(totalVersions) = \(totalPerVersion * totalVersions) file (process \(processMs)ms, stage \(stageMs)ms)")

        let tTunnel = Date()
        let tunnelOK = await tunnelTask.value
        let tunnelMs = Int(Date().timeIntervalSince(tTunnel) * 1000)
        if !tunnelOK {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không kết nối được tới VPN."])
        }
        onLogUpdate("[3/6] Tunnel OK (await \(tunnelMs)ms)")

        let pairPath = pairingURL.path
        let stagePath = stageDir.path
        let sampleFile = processedFiles.first!.filename

        // ⚡ WorseQuery
        let bq = WorseQuery()
        var perVersionTimes: [(String, Int)] = []
        let tWrite = Date()

        for (idx, versionName) in versions.enumerated() {
            let targetPath = "/var/mobile/Library/Caches/\(versionName)"
            let tVer = Date()
            let isLastVersion = (idx == totalVersions - 1)
            let shouldVerify = verifyAfterWrite && (verifyAllVersions || isLastVersion)
            onLogUpdate("[4/6] Version \(idx+1)/\(totalVersions): \(versionName)\(shouldVerify ? " (verify)" : "")")

            try await writeOneVersion(
                versionName: versionName,
                targetPath: targetPath,
                stagePath: stagePath,
                pairPath: pairPath,
                sampleFile: sampleFile,
                totalPerVersion: totalPerVersion,
                shouldVerify: shouldVerify,
                bq: bq,
                onLogUpdate: onLogUpdate
            )

            let ms = Int(Date().timeIntervalSince(tVer) * 1000)
            perVersionTimes.append((versionName, ms))
            let runningTotal = Int(Date().timeIntervalSince(startTime) * 1000)
            onLogUpdate(String(format: "  ✅ %@: %@ (%dms) — tổng %.2fs",
                               versionName,
                               shouldVerify ? "verified" : "done",
                               ms,
                               Double(runningTotal) / 1000))
        }

        let writeMs = Int(Date().timeIntervalSince(tWrite) * 1000)
        let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)

        onLogUpdate("[5/6] Done")
        onLogUpdate("  Tổng file: \(totalPerVersion * totalVersions)")
        for (name, ms) in perVersionTimes {
            onLogUpdate("  • \(name): \(ms)ms")
        }
        onLogUpdate("  Write: \(writeMs)ms")
        onLogUpdate(String(format: "  ⏱ Elapsed (từ lúc ấn Apply): %.2fs", Double(totalMs) / 1000))
        onLogUpdate("[6/6] Reset Theme & Reboot để áp dụng")
    }

    // MARK: - Reset ⚡ (WorseQuery)
    func resetTheme(store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        guard activeTaskID == nil else { return }
        let myID = UUID()
        activeTaskID = myID
        isProcessing = true
        defer {
            if activeTaskID == myID { activeTaskID = nil }
            isProcessing = false
        }

        let telephony = self.store.globalTelephonyVersion
        var seen = Set<String>()
        let versions = telephony.targetFolders.filter { seen.insert($0).inserted }
        let cacheDirs = versions.map { "/var/mobile/Library/Caches/\($0)" }

        let bq = WorseQuery()
        for dir in cacheDirs {
            if bq.grantAccess(atPath: dir).0 {
                try? FileManager.default.removeItem(atPath: dir)
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
        onLogUpdate("Đã xoá Passcode Theme (\(versions.count) folder: \(versions.joined(separator: ", ")))")
        onLogUpdate("Đang khởi động lại...")
        try await Task.sleep(nanoseconds: UInt64(rebootDelayMs) * 1_000_000)
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
        case .invalidFormat:     return "Định dạng theme không hợp lệ (chỉ hỗ trợ .zip, .passthm, .3105pass)."
        }
    }
}