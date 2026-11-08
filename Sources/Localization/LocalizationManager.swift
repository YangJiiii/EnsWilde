//
//  LocalizationManager.swift
//  EnsWilde
//

import Foundation

/// Manager for handling localized strings
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "SelectedLanguage")
            loadStrings()
        }
    }
    
    private var strings: [String: String] = [:]
    private var englishStrings: [String: String] = [:]
    
    private init() {
        // Load saved language preference or default to English
        self.currentLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        loadEnglishStrings()
        loadStrings()
    }
    
    /// Get localized string for key
    func string(for key: String) -> String {
        // Try current language first
        if let value = strings[key], !value.isEmpty {
            return value
        }
        // Fallback to English
        if let value = englishStrings[key], !value.isEmpty {
            return value
        }
        // 🔴 FIX lỗi `_`: humanize key thay vì trả raw key
        #if DEBUG
        print("⚠️ Missing i18n key: \(key)")
        #endif
        return key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    
    /// Load English strings for fallback
    private func loadEnglishStrings() {
        // Try to load from Resources directory (bundled with app)
        if let resourceURL = Bundle.main.resourceURL {
            let resourcePath = resourceURL.appendingPathComponent("en.json")
            if let data = try? Data(contentsOf: resourcePath),
               let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
                englishStrings = loaded
                return
            }
        }
        
        // Try as main bundle resource
        if let bundlePath = Bundle.main.path(forResource: "en", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            englishStrings = loaded
            return
        }
        
        englishStrings = [:]
    }
    
    /// Load strings for current language
    private func loadStrings() {
        // Try to load from Documents directory first (downloaded languages)
        let documentsPath = URL.documentsDirectory
            .appendingPathComponent("Languages")
            .appendingPathComponent("\(currentLanguage).json")
        
        if let data = try? Data(contentsOf: documentsPath),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            strings = loaded
            objectWillChange.send()
            return
        }
        
        // Try to load from Resources directory (bundled with app)
        if let resourceURL = Bundle.main.resourceURL {
            let resourcePath = resourceURL.appendingPathComponent("\(currentLanguage).json")
            if let data = try? Data(contentsOf: resourcePath),
               let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
                strings = loaded
                objectWillChange.send()
                return
            }
        }
        
        // Try as main bundle resource
        if let bundlePath = Bundle.main.path(forResource: currentLanguage, ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            strings = loaded
            objectWillChange.send()
            return
        }
        
        // Last resort: load en.json from Resources as fallback
        if currentLanguage != "en", let resourceURL = Bundle.main.resourceURL {
            let enPath = resourceURL.appendingPathComponent("en.json")
            if let data = try? Data(contentsOf: enPath),
               let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
                strings = loaded
                objectWillChange.send()
                return
            }
        }
        
        // Final fallback: empty strings
        strings = [:]
        objectWillChange.send()
    }
    
    /// Check if a language file exists locally
    func hasLanguage(_ code: String) -> Bool {
        return LanguageFileUtility.hasLanguageFile(code)
    }
}

// MARK: - Convenience Functions

/// Get localized string (shorthand)
func L(_ key: String) -> String {
    return LocalizationManager.shared.string(for: key)
}