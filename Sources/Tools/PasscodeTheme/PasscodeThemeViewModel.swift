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

    // MARK: - Import (nhận MỌI zip/passthm có ảnh)
    func importTheme(from sourceURL: URL, name: String) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let result = try await Task.detached(priority: .userInitiated) {
            () -> (PasscodeTheme, PasscodeTheme.DetectedSize) in
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

            let tempZipURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: tempZipURL) }

            let data = try Data(contentsOf: sourceURL)
            try data.write(to: tempZipURL)

            let newTheme = PasscodeTheme(name: name)
            let themeFolder = newTheme.themeFolderURL
            try? FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)

            // 1) Detect size từ tên file hoặc path bất kỳ có _big/_small
            let detectedSize = PasscodeThemeViewModel.detectSizeFromAnyPath(zipURL: tempZipURL)

            // 2) Giải nén (dùng ZIPFoundation vì ổn định, không cần FFI)
            do {
                try FileManager.default.unzipItem(at: tempZipURL, to: themeFolder)
            } catch {
                try? FileManager.default.removeItem(at: themeFolder)
                throw PasscodeThemeError.invalidFormat
            }

            // 3) FLATTEN: đệ quy tìm mọi ảnh có digit trong tên → move lên root
            try PasscodeThemeViewModel.flattenAllImages(themeFolder: themeFolder)

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

    // MARK: - Detect size (bất kỳ path nào)
    nonisolated static private func detectSizeFromAnyPath(zipURL: URL) -> PasscodeTheme.DetectedSize {
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

    // MARK: - FLATTEN: đệ quy mọi ảnh, giữ 1 ảnh/digit
    nonisolated static private func flattenAllImages(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: themeFolder.path) else { return }

        var movedDigits = Set<String>()
        var filesToMove: [(src: URL, destName: String)] = []

        while let rel = enumerator.nextObject() as? String {
            // Bỏ qua folder ẩn và __MACOSX
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

        // Copy tất cả file tìm được lên root
        for item in filesToMove {
            let destURL = themeFolder.appendingPathComponent(item.destName)
            try? fm.removeItem(at: destURL)
            try? fm.copyItem(at: item.src, to: destURL)
        }

        // Dọn subfolder
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

    nonisolated static private func extractDigitStatic(from filename: String) -> String? {
        let stem = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "--white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-white", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "@2x", with: "")
            .replacingOccurrences(of: "@3x", with: "")

        // AirCard regex: (?:^[a-zA-Z]+-)?([0-9*#])
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
        // Fallback: tìm digit đầu tiên
        for ch in stem {
            if "0123456789".contains(ch) { return String(ch) }
        }
        return nil
    }

    nonisolated private func extractDigit(from filename: String) -> String? {
        return PasscodeThemeViewModel.extractDigitStatic(from: filename)
    }

    // MARK: - Ma trận tạo file (FILTER theo lựa chọn)
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
            let sourceURL = theme.themeFolderURL.appendingPathComponent(filename)
            guard let digit = extractDigit(from: filename) else { continue }
            guard let image = UIImage(contentsOfFile: sourceURL.path) else { continue }
            let processedImage = resizeImage(image, for: theme.keySize, detectedSize: theme.detectedSize)
            guard let imageData = processedImage.pngData() else { continue }

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
        return processedFiles
    }

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

    // MARK: - Apply Theme (ghi theo telephonyVersion.targetFolders)
    func applyTheme(_ theme: PasscodeTheme, store: ToolStore, onLogUpdate: @escaping (String) -> Void) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let language = self.store.globalCustomPrefix
        let boldMode = self.store.globalBoldMode
        let telephony = self.store.globalTelephonyVersion
        let versions = telephony.targetFolders

        onLogUpdate("Preparing (Lang: \(language.displayName), Bold: \(boldMode.rawValue), Ver: \(telephony.displayName))...")

        // 1. Tạo ma trận file (chỉ 1 lần, dùng chung cho các version)
        let processedFiles = try processThemeFiles(theme: theme, language: language, boldMode: boldMode)
        guard !processedFiles.isEmpty else { throw PasscodeThemeError.noImagesProcessed }
        onLogUpdate("Đã tạo \(processedFiles.count) file × \(versions.count) version = \(processedFiles.count * versions.count) file cần ghi.")

        let pairingURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            throw NSError(domain: "AirLift", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy Pairing File."])
        }
        guard NetworkStatus.isVPNTunnelPresent() else {
            throw NSError(domain: "AirLift", code: -10, userInfo: [NSLocalizedDescriptionKey: "VPN chưa bật."])
        }

        // 2. Tạo temp folder
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirLiftPayload_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for (filename, data) in processedFiles {
            try data.write(to: tempDir.appendingPathComponent(filename))
        }
        if theme.keySize == .big {
            FileManager.default.createFile(atPath: tempDir.appendingPathComponent("_big").path, contents: Data())
        }

        // 3. Dò tunnel
        onLogUpdate("Đang dò tunnel IP...")
        guard await AirliftHostResolver.bestAvailable(log: onLogUpdate) != nil else {
            throw NSError(domain: "AirLift", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không kết nối được tới VPN."])
        }

        // 4. Ghi tuần tự từng version (KHÔNG parallel để tránh nghẽn tunnel)
        let targetParentDir = "/var/mobile/Library/Caches"
        let bq = BadQuery()

        for (idx, versionName) in versions.enumerated() {
            let targetPath = "\(targetParentDir)/\(versionName)"
            onLogUpdate("[\(idx+1)/\(versions.count)] Đang xoá cache cũ trong \(versionName)...")
            if bq.grantAccess(atPath: targetPath).0 {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: targetPath) {
                    for file in files {
                        try? FileManager.default.removeItem(atPath: (targetPath as NSString).appendingPathComponent(file))
                    }
                }
            }

            onLogUpdate("[\(idx+1)/\(versions.count)] Đang ghi \(processedFiles.count) file vào \(versionName)...")
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let (cb, ctx) = AirliftFFIBridge.makeLogCallback(onLine: onLogUpdate)
                    defer { AirliftFFIBridge.releaseLogCallback(ctx) }
                    var errPtr: UnsafeMutablePointer<CChar>? = nil
                    let res = al_exploit_inject_folder(
                        pairingURL.path,
                        tempDir.path,
                        targetParentDir,
                        versionName,
                        cb,
                        ctx,
                        &errPtr
                    )
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
            onLogUpdate("[\(idx+1)/\(versions.count)] ✅ Xong \(versionName).")
        }

        onLogUpdate("✅ Tất cả \(versions.count) version đã ghi xong. Bấm 'Reset Theme & Reboot' để áp dụng.")
    }

    // MARK: - Reset
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
        case .noImagesFound:     return "Không tìm thấy ảnh trong ZIP. Đảm bảo zip có chứa file .png/.jpg/.jpeg với số 0-9 trong tên."
        case .noImagesProcessed: return "Không xử lý được ảnh."
        case .invalidFormat:     return "Định dạng theme không hợp lệ."
        }
    }
}