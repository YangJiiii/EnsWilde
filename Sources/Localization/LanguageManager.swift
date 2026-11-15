//
//  LanguageManager.swift
//  EnsWilde
//

import Foundation

/// Manager for downloading and managing language files
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    // URL to the online language list (GitHub raw content)
    private let languageListURL = URL(string: "https://raw.githubusercontent.com/YangJiiii/EnsWilde/main/languages.json")!
    
    @Published var availableLanguages: [LanguageInfo] = []
    @Published var downloadedLanguages: Set<String> = []
    @Published var isLoading = false
    @Published var lastError: String?
    
    private let documentsLanguagesDir: URL
    
    private init() {
        documentsLanguagesDir = URL.documentsDirectory.appendingPathComponent("Languages")
        createLanguagesDirectory()
        loadDownloadedLanguages()
    }
    
    /// Create Languages directory if it doesn't exist
    private func createLanguagesDirectory() {
        if !FileManager.default.fileExists(atPath: documentsLanguagesDir.path) {
            try? FileManager.default.createDirectory(
                at: documentsLanguagesDir,
                withIntermediateDirectories: true
            )
        }
    }
    
    /// Load list of downloaded languages
    private func loadDownloadedLanguages() {
        var languages = Set<String>()
        
        // Add downloaded languages from Documents
        if let files = try? FileManager.default.contentsOfDirectory(atPath: documentsLanguagesDir.path) {
            for file in files {
                guard file.hasSuffix(".json"), !file.hasSuffix(".meta.json") else { continue }
                languages.insert(file.replacingOccurrences(of: ".json", with: ""))
            }
        }
        
        // Add bundled languages from Resources
        if let resourceURL = Bundle.main.resourceURL,
           let files = try? FileManager.default.contentsOfDirectory(atPath: resourceURL.path) {
            for file in files {
                guard file.hasSuffix(".json") else { continue }
                languages.insert(file.replacingOccurrences(of: ".json", with: ""))
            }
        }
        
        downloadedLanguages = languages
    }
    
    /// Fetch available languages from online repository
    func fetchAvailableLanguages() async {
        await MainActor.run { isLoading = true }
        
        do {
            var request = URLRequest(url: languageListURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run {
                    lastError = L("error_language_fetch_failed")
                    isLoading = false
                }
                return
            }
            
            let languageList = try JSONDecoder().decode(LanguageListResponse.self, from: data)
            
            await MainActor.run {
                availableLanguages = languageList.languages
                loadDownloadedLanguages()
                isLoading = false
                lastError = nil
            }
        } catch {
            await MainActor.run {
                lastError = L("msg_error_generic").replacingOccurrences(of: "{error}", with: error.localizedDescription)
                isLoading = false
            }
        }
    }
    
    /// Download a language file
    func downloadLanguage(_ language: LanguageInfo) async -> Bool {
        guard let url = URL(string: language.downloadURL) else {
            await MainActor.run {
                lastError = L("error_language_download_invalid_url").replacingOccurrences(of: "{language}", with: language.name)
            }
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run {
                    lastError = L("error_language_download_failed").replacingOccurrences(of: "{language}", with: language.name)
                }
                return false
            }
            
            // Validate JSON before saving
            _ = try JSONDecoder().decode([String: String].self, from: data)
            
            // Save to Documents/Languages/
            let filePath = documentsLanguagesDir.appendingPathComponent("\(language.code).json")
            try data.write(to: filePath)
            
            // Also save metadata
            let metadataPath = documentsLanguagesDir.appendingPathComponent("\(language.code).meta.json")
            let metadataData = try JSONEncoder().encode(language)
            try metadataData.write(to: metadataPath)
            
            await MainActor.run {
                downloadedLanguages.insert(language.code)
                lastError = nil
            }
            
            return true
        } catch {
            await MainActor.run {
                lastError = L("error_language_download_error")
                    .replacingOccurrences(of: "{language}", with: language.name)
                    .replacingOccurrences(of: "{error}", with: error.localizedDescription)
            }
            return false
        }
    }
    
    /// Delete a downloaded language
    func deleteLanguage(_ code: String) {
        let filePath = documentsLanguagesDir.appendingPathComponent("\(code).json")
        let metadataPath = documentsLanguagesDir.appendingPathComponent("\(code).meta.json")
        
        try? FileManager.default.removeItem(at: filePath)
        try? FileManager.default.removeItem(at: metadataPath)
        
        downloadedLanguages.remove(code)
    }
    
    /// Check if a language is downloaded or bundled
    func isDownloaded(_ code: String) -> Bool {
        return LanguageFileUtility.hasLanguageFile(code)
    }
    
    /// Get language version if downloaded
    func getLanguageVersion(_ code: String) -> Int? {
        let metadataPath = documentsLanguagesDir.appendingPathComponent("\(code).meta.json")
        guard let data = try? Data(contentsOf: metadataPath),
              let language = try? JSONDecoder().decode(LanguageInfo.self, from: data) else {
            return nil
        }
        return language.version
    }
    
    /// Check if an update is available for a language
    func hasUpdate(_ language: LanguageInfo) -> Bool {
        guard let currentVersion = getLanguageVersion(language.code) else {
            return false
        }
        return language.version > currentVersion
    }
}

// MARK: - LocalizationManager Bridge
//
// Cầu nối cho `AboutView` (Sources/UI/SettingsView.swift).
//
// `AboutView` đọc `localizationManager.availableLanguages` và gọi
// `localizationManager.fetchAvailableLanguages()` — trong khi toàn bộ logic
// tải danh sách ngôn ngữ nằm trên `LanguageManager.shared`.
//
// Extension này:
//   1. Gọi `LanguageManager.shared.fetchAvailableLanguages()` (giữ nguyên logic cũ).
//   2. Copy kết quả `LanguageManager.shared.availableLanguages` sang
//      `LocalizationManager.shared.availableLanguages` để SwiftUI view
//      (đang `@ObservedObject localizationManager`) nhận được update.
//
// Không thay đổi UI, không thay đổi logic, chỉ bổ sung entry point bị thiếu.
extension LocalizationManager {
    func fetchAvailableLanguages() async {
        await LanguageManager.shared.fetchAvailableLanguages()
        let langs = LanguageManager.shared.availableLanguages
        await MainActor.run {
            self.availableLanguages = langs
        }
    }
}