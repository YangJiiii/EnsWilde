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

    init(store: PasscodeThemeStore) { self.store = store }

    // MARK: - Import (nhận mọi ZIP/Passthm, không auto-set keySize)
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
        // KHÔNG auto-set keySize — user tự chọn Small/Big trong ThemeDetailView
        self.store.addTheme(themeWithSize)
    }

    func importDefaultPasscode(from sourceURL: URL, name: String, themeStore: PasscodeThemeStore) async throws {
        try await importTheme(from: sourceURL, name: name)
    }

    // MARK: - Detect Size (nhận diện thông minh như AirCard)

    /// Thứ tự ưu tiên:
    /// 1. `_big` marker → big
    /// 2. `_small` marker → small
    /// 3. Folder `TelephonyUI-10` (iOS 18+) không có marker → mặc định big
    /// 4. Folder `TelephonyUI-9` (iOS 16-17) không có marker → big
    /// 5. Folder `TelephonyUI-8` (iOS 14-15) không có marker → small
    /// 6. Không có → unknown
    nonisolated static private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            var hasBig = false
            var hasSmall = false
            var hasTUI10 = false
            var hasTUI9 = false
            var hasTUI8 = false

            for entry in archive {
                let lower = entry.path.lowercased()
                if lower.hasSuffix("_big") || lower.contains("_big/") { hasBig = true }
                if lower.hasSuffix("_small") || lower.contains("_small/") { hasSmall = true }
                if lower.contains("telephonyui-10") { hasTUI10 = true }
                if lower.contains("telephonyui-9")  { hasTUI9 = true }
                if lower.contains("telephonyui-8")  { hasTUI8 = true }
            }

            if hasBig { return .big }
            if hasSmall { return .small }
            if hasTUI10 || hasTUI9 { return .big }
            if hasTUI8 { return .small }
            return .unknown
        } catch { return .unknown }
    }

    // MARK: - Extract Images (đệ quy + chọn file tốt nhất như AirCard)

    /// Nhận diện mọi cấu trúc ZIP:
    /// - `TelephonyUI-10/en-1---white.png`
    /// - `en-1---white.png`
    /// - `1.png`
    /// - `com.apple.xxx/en-1-A B C--white-bold.png`
    /// - `.passthm/TelephonyUI-9/...`
    /// - Bất kỳ folder lồng sâu nào
    /// 
    /// Ưu tiên chọn file chuẩn AirCard (có `---white` hoặc `--white`), fallback file `N.png`.
    nonisolated static private func extractImagesRecursively(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: themeFolder.path) else { return }

        // Extensions được hỗ trợ (mở rộng như AirCard)
        let validExts: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "tif", "bmp"]

        // Lưu file tốt nhất cho mỗi digit
        var bestPerDigit: [String: (priority: Int, url: URL)] = [:]

        while let rel = enumerator.nextObject() as? String {
            if rel.hasPrefix(".") || rel.contains("__MACOSX") || rel.contains("/_") { continue }
            let fullURL = themeFolder.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            let ext = (rel as NSString).pathExtension.lowercased()
            guard validExts.contains(ext) else { continue }

            let filename = (rel as NSString).lastPathComponent.lowercased()
            guard let digit = extractDigitStatic(from: filename) else { continue }

            // Ưu tiên: file chuẩn AirCard > file có prefix ngôn ngữ > file N.png
            var priority = 1
            if filename.contains("---white")    { priority = 10 }
            else if filename.contains("--white") { priority = 9 }
            else if filename.contains("-white")  { priority = 8 }
            else if filename.range(of: #"^[a-z]{2,3}-"#, options: .regularExpression) != nil { priority = 5 }

            if let existing = bestPerDigit[digit] {
                if priority > existing.priority {
                    bestPerDigit[digit] = (priority, fullURL)
                }
            } else {
                bestPerDigit[digit] = (priority, fullURL)
            }
        }

        // Copy file tốt nhất ra root với tên N.png
        for (digit, entry) in bestPerDigit {
            let destURL = themeFolder.appendingPathComponent("\(digit).png")
            try? fm.removeItem(at: destURL)
            try? fm.copyItem(at: entry.url, to: destURL)
        }

        // Xoá thư mục con để làm phẳng
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

    // MARK: - Extract Digit (nhận siêu nhiều định dạng tên file)

    /// Hỗ trợ:
    /// - `en-1---white.png` → 1
    /// - `en-1-A B C--white-bold.png` → 1
    /// - `en-1-ABC--white.png` → 1
    /// - `1.png` → 1
    /// - `1@2x.png` → 1
    /// - `com.apple.xxx-en-1---white.png` → 1
    /// - `key_5_white.png` → 5
    /// - `TelephonyUI-10/en-0-+--white.png` → 0
    nonisolated static func extractDigitStatic(from filename: String) -> String? {
        var stem = (filename as NSString).deletingPathExtension.lowercased()

        // Bỏ hậu tố AirCard
        for suffix in ["--white", "-white", "-bold", "@2x", "@3x", "@1x"] {
            stem = stem.replacingOccurrences(of: suffix, with: "")
        }

        // Pattern 1: Digit đứng độc lập (bao quanh bởi - _ . hoặc đầu/cuối)
        let pattern = #"(?:^|[-_.])([0-9])(?:[-_.]|$)"#
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = stem as NSString
            if let m = re.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                let r = m.range(at: 1)
                if r.location != NSNotFound { return ns.substring(with: r) }
            }
        }

        // Pattern 2: File chỉ có tên N.png → sau khi bỏ suffix chỉ còn 1 ký tự số
        let trimmed = stem.trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        if trimmed.count == 1, let d = trimmed.first, "0123456789".contains(d) {
            return String(d)
        }

        // Fallback: digit đầu tiên
        for c in stem {
            if "0123456789".contains(c) { return String(c) }
        }
        return nil
    }

    // MARK: - Matrix File (giống hệt AirCard, giữ nguyên)

    nonisolated func processThemeFiles(
        theme: PasscodeTheme,
        language: PasscodeTheme.PrefixLanguage,
        boldMode: PasscodeTheme.BoldMode
    ) throws -> [(filename: String, imageData: Data)] {

        var processedFiles: [(String, Data)] = []
        let imageFiles = theme.getImageFiles()
        guard !imageFiles.isEmpty else { throw PasscodeThemeError.noImagesFound }

        let allLocales = ["en", "other", "ru", "uk", "es", "fr", "de", "it", "pt", "tr", "pl", "nl", "ja", "ko", "zh", "ar", "he"]
        let locales: [String]
        if language == .universal {
            locales = allLocales
        } else if language == .other {
            locales = ["other"]
        } else {
            locales = [language.rawValue, "other"]
        }

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

        for filename in imageFiles {
            autoreleasepool {
                let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
                guard let digit = PasscodeThemeViewModel.extractDigitStatic(from: filename) else { return }
                guard let image = UIImage(contentsOfFile: sourceURL.path) else { return }
                let processedImage = resizeImage(image, for: theme.keySize, detectedSize: theme.detectedSize)
                guard let imageData = processedImage.pngData() else { return }

                let stdSub = subtexts[digit] ?? ""
                let ruSub = ruSubtexts[digit]
                let ukSub = ukSubtexts[digit]

                for lang in locales {
                    for bld in boldSuffixes {
                        processedFiles.append(("\(lang)-\(digit)---white\(bld).png", imageData))

                        if !stdSub.isEmpty {
                            processedFiles.append(("\(lang)-\(digit)-\(stdSub)--white\(bld).png", imageData))
                            let noSpace = stdSub.replacingOccurrences(of: " ", with: "")
                            if noSpace != stdSub {
                                processedFiles.append(("\(lang)-\(digit)-\(noSpace)--white\(bld).png", imageData))
                            }
                        }

                        if lang == "ru" || language == .universal, let sub = ruSub {
                            processedFiles.append(("\(lang)-\(digit)-\(sub)--white\(bld).png", imageData))
                        }
                        if lang == "uk" || language == .universal, let sub = ukSub {
                            processedFiles.append(("\(lang)-\(digit)-\(sub)--white\(bld).png", imageData))
                        }
                    }
                }
            }
        }
        return processedFiles
    }

    // MARK: - Resize (logic EnsWilde cũ)
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

    // MARK: - Apply Theme (dùng al_exploit_write_dir, xoá cache trước)
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

        // 1. Tạo ma trận file
        let processedFiles = try processThemeFiles(theme: theme, language: language, boldMode: boldMode)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        onLogUpdate("Đã tạo \(processedFiles.count) file.")

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."])
        }

        // 2. Stage file
        let stageThemeDir = FileManager.default.temporaryDirectory.appendingPathComponent("airlift_passthm_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stageThemeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stageThemeDir) }

        let tStage = Date()
        for (filename, data) in processedFiles {
            try? data.write(to: stageThemeDir.appendingPathComponent(filename), options: .atomic)
        }

        // Marker _big chỉ tạo khi keySize == .big (EnsWilde cũ — giúp phím liền mạch)
        if theme.keySize == .big {
            try? Data().write(to: stageThemeDir.appendingPathComponent("_big"))
        }
        
        let actualStaged = (try? FileManager.default.contentsOfDirectory(atPath: stageThemeDir.path))?.count ?? 0
        onLogUpdate("📊 Staged \(actualStaged) files in \(Int(Date().timeIntervalSince(tStage)))s.")

        // 3. Ghi qua Airlift
        onLogUpdate("Đang dò tunnel IP...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không kết nối được tới VPN."])
        }

        let bq = BadQuery()

        for (idx, versionName) in versions.enumerated() {
            let targetPath = "/var/mobile/Library/Caches/\(versionName)"
            let tVer = Date()
            onLogUpdate("[\(idx+1)/\(versions.count)] Đang ghi vào \(versionName)...")

            // Xoá cache cũ
            if bq.grantAccess(atPath: targetPath).0 {
                try? FileManager.default.removeItem(atPath: targetPath)
            }
            try? FileManager.default.createDirectory(atPath: targetPath, withIntermediateDirectories: true)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                    defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                    var errPtr: UnsafeMutablePointer<CChar>? = nil
                    let res = pairingURL.path.withCString { pairC in
                        stageThemeDir.path.withCString { srcC in
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
            onLogUpdate("  ✅ \(versionName) xong sau \(Int(Date().timeIntervalSince(tVer)))s.")
        }

        onLogUpdate("🎉 Done in \(Int(Date().timeIntervalSince(startTime)))s. Bấm 'Reset Theme & Reboot' để áp dụng.")
    }

    private func detectedName(_ d: PasscodeTheme.DetectedSize) -> String {
        switch d {
        case .unknown: return "Unknown"
        case .small:   return "Small (202px)"
        case .big:     return "Big (287px)"
        }
    }

    // MARK: - Reset (Giữ nguyên)
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
                if let files = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                    for file in files {
                        try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(file))
                    }
                }
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