//
//  LocalizationManager.swift
//  EnsWilde
//

import Foundation

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
        self.currentLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
        loadEnglishStrings()
        loadStrings()
    }
    
    /// Get localized string for key
    func string(for key: String) -> String {
        if let value = strings[key], !value.isEmpty {
            return value
        }
        if let value = englishStrings[key], !value.isEmpty {
            return value
        }
        // 🔴 FIX: không trả raw key có `_`, humanize để dễ đọc khi debug
        #if DEBUG
        print("⚠️ Missing i18n key: \(key)")
        #endif
        return key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    
    private func loadEnglishStrings() {
        if let resourceURL = Bundle.main.resourceURL {
            let resourcePath = resourceURL.appendingPathComponent("en.json")
            if let data = try? Data(contentsOf: resourcePath),
               let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
                englishStrings = loaded
                return
            }
        }
        if let bundlePath = Bundle.main.path(forResource: "en", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            englishStrings = loaded
            return
        }
        englishStrings = [:]
    }
    
    private func loadStrings() {
        let documentsPath = URL.documentsDirectory
            .appendingPathComponent("Languages")
            .appendingPathComponent("\(currentLanguage).json")
        
        if let data = try? Data(contentsOf: documentsPath),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            strings = loaded
            objectWillChange.send()
            return
        }
        
        if let resourceURL = Bundle.main.resourceURL {
            let resourcePath = resourceURL.appendingPathComponent("\(currentLanguage).json")
            if let data = try? Data(contentsOf: resourcePath),
               let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
                strings = loaded
                objectWillChange.send()
                return
            }
        }
        
        if let bundlePath = Bundle.main.path(forResource: currentLanguage, ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            strings = loaded
            objectWillChange.send()
            return
        }
        
        if currentLanguage != "en", let resourceURL = Bundle.main.resourceURL {
            let enPath = resourceURL.appendingPathComponent("en.json")
            if let data = try? Data(contentsOf: enPath),
               let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
                strings = loaded
                objectWillChange.send()
                return
            }
        }
        
        strings = [:]
        objectWillChange.send()
    }
    
    func hasLanguage(_ code: String) -> Bool {
        return LanguageFileUtility.hasLanguageFile(code)
    }
}

func L(_ key: String) -> String {
    return LocalizationManager.shared.string(for: key)
}