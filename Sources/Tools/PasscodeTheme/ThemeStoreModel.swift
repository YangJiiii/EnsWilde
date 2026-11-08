import Foundation
import ZIPFoundation

// MARK: - Models

struct ThemeRepository: Codable, Identifiable {
    let url: String
    var name: String
    var iconURL: String?
    var isIndex: Bool
    
    var id: String { url }
    var jsonURL: URL? { URL(string: url) }
}

struct IndexedRepository: Codable, Identifiable {
    let name: String
    let baseURL: String
    let themesURL: String
    var id: String { baseURL }
    var cleanBaseURL: String { baseURL.hasSuffix("/") ? baseURL : baseURL + "/" }
    var themesJSONURL: URL? { URL(string: themesURL) }
}

struct RemoteTheme: Identifiable {
    let name: String
    let description: String
    let url: String
    let preview: String
    let authors: String
    let baseURL: String
    var id: String { url }
    var fullURL: URL? {
        let clean = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        return URL(string: clean + url)
    }
    var previewURL: URL? {
        let clean = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        return URL(string: clean + preview)
    }
}

// MARK: - Manager

@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var repositories: [ThemeRepository] = []
    @Published var indexedRepositories: [IndexedRepository] = []
    @Published var remoteThemes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var downloadingThemes: Set<String> = []
    @Published var selectedRepository: ThemeRepository?
    @Published var selectedIndexedRepo: IndexedRepository?
    
    private static let defaultRepo = ThemeRepository(
        url: "https://raw.githubusercontent.com/YangJiiii/EnsWilde/refs/heads/main/themes-store/index.json",
        name: "YangJiii - Passcode",
        iconURL: nil,
        isIndex: true
    )
    
    private let savedReposKey = "enswilde.themeStoreRepos"
    
    init() {
        loadSavedRepos()
    }
    
    // MARK: - Persistence
    
    private func loadSavedRepos() {
        if let data = UserDefaults.standard.data(forKey: savedReposKey),
           let decoded = try? JSONDecoder().decode([ThemeRepository].self, from: data),
           !decoded.isEmpty {
            repositories = decoded
        } else {
            repositories = [Self.defaultRepo]
            saveRepos()
        }
    }
    
    private func saveRepos() {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: savedReposKey)
        }
    }
    
    func addRepo(urlString: String) async throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw ThemeStoreError.invalidURL
        }
        guard !repositories.contains(where: { $0.url == trimmed }) else {
            throw ThemeStoreError.duplicateRepo
        }
        
        let repo = try await parseRepoMetadata(url: url)
        repositories.append(repo)
        saveRepos()
    }
    
    func removeRepo(_ repo: ThemeRepository) {
        repositories.removeAll { $0.id == repo.id }
        saveRepos()
    }
    
    // MARK: - DYNAMIC JSON PARSER (Hỗ trợ mọi format)
    
    private func parseRepoMetadata(url: URL) async throws -> ThemeRepository {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ThemeStoreError.invalidJSON
        }
        
        let baseURLString = url.deletingLastPathComponent().absoluteString
        let defaultName = Self.deriveNameFromURL(url)
        
        // 1. Check if it's an Index (Array of objects with baseURL/themesURL)
        if let array = json as? [[String: Any]], array.contains(where: { $0["baseURL"] != nil && $0["themesURL"] != nil }) {
            return ThemeRepository(url: url.absoluteString, name: defaultName, iconURL: nil, isIndex: true)
        }
        
        // 2. Check if it's a dictionary (Object)
        if let dict = json as? [String: Any] {
            let name = dict["name"] as? String ?? defaultName
            var icon: String? = nil
            
            if let iconStr = dict["icon"] as? String {
                icon = iconStr.hasPrefix("http") ? iconStr : baseURLString + iconStr
            }
            
            // If it has "themes" or "packages", it's a direct repo
            if dict["themes"] != nil || dict["packages"] != nil {
                return ThemeRepository(url: url.absoluteString, name: name, iconURL: icon, isIndex: false)
            }
        }
        
        // 3. Check if it's an array of themes (direct)
        if let array = json as? [[String: Any]], array.contains(where: { $0["url"] != nil || $0["download"] != nil }) {
            return ThemeRepository(url: url.absoluteString, name: defaultName, iconURL: nil, isIndex: false)
        }
        
        throw ThemeStoreError.invalidJSON
    }
    
    private static func deriveNameFromURL(_ url: URL) -> String {
        let comps = url.pathComponents.filter { $0 != "/" }
        if comps.count >= 2 { return comps[1].replacingOccurrences(of: "-", with: " ") }
        return url.deletingPathExtension().lastPathComponent
    }
    
    // MARK: - Fetching Data
    
    func fetchIndexedRepos(from repo: ThemeRepository) async {
        isLoading = true; errorMessage = nil; indexedRepositories = []; selectedRepository = repo
        
        guard let url = repo.jsonURL else { isLoading = false; return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Parse index format
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                indexedRepositories = array.compactMap { dict in
                    guard let name = dict["name"] as? String,
                          let base = dict["baseURL"] as? String,
                          let themes = dict["themesURL"] as? String else { return nil }
                    return IndexedRepository(name: name, baseURL: base, themesURL: themes)
                }
            }
        } catch {
            errorMessage = "Failed to load index: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func fetchThemes(from repo: ThemeRepository) async {
        isLoading = true; errorMessage = nil; remoteThemes = []; selectedRepository = repo; selectedIndexedRepo = nil
        
        guard let url = repo.jsonURL else { isLoading = false; return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let baseURL = url.deletingLastPathComponent().absoluteString
            remoteThemes = try parseThemes(from: data, baseURL: baseURL)
        } catch {
            errorMessage = "Failed to load themes: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func fetchThemes(from indexed: IndexedRepository) async {
        isLoading = true; errorMessage = nil; remoteThemes = []; selectedIndexedRepo = indexed
        
        guard let url = indexed.themesJSONURL else { isLoading = false; return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            remoteThemes = try parseThemes(from: data, baseURL: indexed.cleanBaseURL)
        } catch {
            errorMessage = "Failed to load themes: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    private func parseThemes(from data: Data, baseURL: String) throws -> [RemoteTheme] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        
        var rawArray: [[String: Any]] = []
        
        // Extract array of themes
        if let arr = json as? [[String: Any]] {
            rawArray = arr
        } else if let dict = json as? [String: Any] {
            if let themes = dict["themes"] as? [[String: Any]] { rawArray = themes }
            else if let packages = dict["packages"] as? [[String: Any]] { rawArray = packages }
        }
        
        return rawArray.compactMap { dict in
            let name = dict["name"] as? String ?? "Unknown"
            let desc = (dict["description"] as? String) ?? (dict["summary"] as? String) ?? ""
            let url = (dict["url"] as? String) ?? (dict["download"] as? String) ?? ""
            let preview = (dict["preview"] as? String) ?? (dict["icon"] as? String) ?? ""
            let authors = (dict["authors"] as? String) ?? (dict["author"] as? String) ?? "Unknown"
            
            guard !url.isEmpty else { return nil }
            return RemoteTheme(name: name, description: desc, url: url, preview: preview, authors: authors, baseURL: baseURL)
        }
    }
    
    // MARK: - Navigation
    func backToRepositories() {
        selectedRepository = nil; selectedIndexedRepo = nil
        indexedRepositories = []; remoteThemes = []; errorMessage = nil
    }
    
    func backToIndexedRepos() {
        selectedIndexedRepo = nil; remoteThemes = []; errorMessage = nil
    }
    
    // MARK: - Download & Import
    func downloadAndImportTheme(_ theme: RemoteTheme, themeStore: PasscodeThemeStore) async throws {
        guard let downloadURL = theme.fullURL else { throw ThemeStoreError.invalidURL }
        downloadingThemes.insert(theme.id)
        defer { downloadingThemes.remove(theme.id) }
        
        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        let permanentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("passthm")
        try FileManager.default.copyItem(at: tempURL, to: permanentURL)
        
        try await importThemeDirectly(from: permanentURL, name: theme.name, store: themeStore)
        try? FileManager.default.removeItem(at: permanentURL)
    }
    
    private func importThemeDirectly(from sourceURL: URL, name: String, store: PasscodeThemeStore) async throws {
        let newTheme = PasscodeTheme(name: name)
        let themeFolder = newTheme.themeFolderURL
        if !FileManager.default.fileExists(atPath: themeFolder.path) {
            try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        }
        
        let detectedSize = detectSizeFromZIP(at: sourceURL)
        do { try FileManager.default.unzipItem(at: sourceURL, to: themeFolder) }
        catch { try? FileManager.default.removeItem(at: themeFolder); throw ThemeStoreError.unzipFailed }
        
        try extractImagesFromTelephonySubfolder(themeFolder: themeFolder)
        
        var themeWithSize = newTheme
        themeWithSize.detectedSize = detectedSize
        store.addTheme(themeWithSize)
    }
    
    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for entry in archive { if entry.path.hasSuffix("_small") { return .small } }
            for entry in archive { if entry.path.hasSuffix("_big") { return .big } }
            return .unknown
        } catch { return .unknown }
    }
    
    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: themeFolder.path) else { return }
        guard let tele = contents.first(where: { $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI") }) else { return }
        let teleURL = themeFolder.appendingPathComponent(tele)
        guard let images = try? fm.contentsOfDirectory(atPath: teleURL.path) else { return }
        for filename in images {
            let ext = (filename as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            try? fm.moveItem(at: teleURL.appendingPathComponent(filename), to: themeFolder.appendingPathComponent(filename))
        }
        try? fm.removeItem(at: teleURL)
    }
}

enum ThemeStoreError: LocalizedError {
    case invalidURL, unzipFailed, invalidJSON, duplicateRepo
    var errorDescription: String? {
        switch self {
        case .invalidURL:    return "Invalid URL"
        case .unzipFailed:   return "Failed to extract theme"
        case .invalidJSON:   return "Unsupported JSON format"
        case .duplicateRepo: return "Repo already exists"
        }
    }
}