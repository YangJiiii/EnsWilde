import Foundation
import ZIPFoundation

// MARK: - Top-level repo (lưu trong UserDefaults)
struct ThemeRepository: Codable, Identifiable {
    let url: String
    var name: String
    var iconURL: String?   // full URL đã resolve
    var isIndex: Bool      // true = index nhiều sub-repo, false = direct themes
    
    var id: String { url }
    var jsonURL: URL? { URL(string: url) }
}

// MARK: - Sub-repo (chỉ tồn tại khi là index)
struct IndexedRepository: Codable, Identifiable {
    let name: String
    let baseURL: String
    let themesURL: String
    var id: String { baseURL }
    var cleanBaseURL: String { baseURL.hasSuffix("/") ? baseURL : baseURL + "/" }
    var themesJSONURL: URL? { URL(string: themesURL) }
}

// MARK: - Theme model
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

// MARK: - Decode models (hỗ trợ nhiều format JSON)

struct RemoteThemeCodable: Codable {
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String?
    
    enum CodingKeys: String, CodingKey {
        case name, description, url, preview, authors
        case summary, author, download, icon
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Theme"
        description = try c.decodeIfPresent(String.self, forKey: .description)
            ?? c.decodeIfPresent(String.self, forKey: .summary)
        url = try c.decodeIfPresent(String.self, forKey: .url)
            ?? c.decodeIfPresent(String.self, forKey: .download) ?? ""
        preview = try c.decodeIfPresent(String.self, forKey: .preview)
            ?? c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        authors = try c.decodeIfPresent(String.self, forKey: .authors)
            ?? c.decodeIfPresent(String.self, forKey: .author) ?? "Unknown Author"
    }
}

struct RepoJSONCodable: Codable {
    let name: String?
    let description: String?
    let icon: String?
    let themes: [RemoteThemeCodable]?
    let packages: [RemoteThemeCodable]?
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
    
    // Default repo khi chưa có gì
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
    
    // MARK: - Add / Remove
    
    func addRepo(urlString: String) async throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw ThemeStoreError.invalidURL
        }
        guard !repositories.contains(where: { $0.url == trimmed }) else {
            throw ThemeStoreError.duplicateRepo
        }
        
        let repo = try await fetchRepoMetadata(url: url)
        repositories.append(repo)
        saveRepos()
    }
    
    func removeRepo(_ repo: ThemeRepository) {
        repositories.removeAll { $0.id == repo.id }
        saveRepos()
    }
    
    // MARK: - Fetch metadata cho 1 URL (detect format)
    
    private func fetchRepoMetadata(url: URL) async throws -> ThemeRepository {
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Format 1: [IndexedRepository] (index.json của YangJiiii / tương tự)
        if let _ = try? JSONDecoder().decode([IndexedRepository].self, from: data) {
            let name = Self.deriveNameFromURL(url)
            return ThemeRepository(url: url.absoluteString, name: name, iconURL: nil, isIndex: true)
        }
        
        // Format 2: RepoJSONCodable { name, icon, themes/packages }
        if let repoJSON = try? JSONDecoder().decode(RepoJSONCodable.self, from: data) {
            let name = repoJSON.name ?? Self.deriveNameFromURL(url)
            let baseURL = url.deletingLastPathComponent().absoluteString
            let icon = repoJSON.icon.map { resolveIcon($0, baseURL: baseURL) }
            return ThemeRepository(url: url.absoluteString, name: name, iconURL: icon, isIndex: false)
        }
        
        // Format 3: [RemoteThemeCodable] (array themes trực tiếp)
        if let _ = try? JSONDecoder().decode([RemoteThemeCodable].self, from: data) {
            let name = Self.deriveNameFromURL(url)
            return ThemeRepository(url: url.absoluteString, name: name, iconURL: nil, isIndex: false)
        }
        
        throw ThemeStoreError.invalidJSON
    }
    
    private func resolveIcon(_ icon: String, baseURL: String) -> String? {
        if icon.hasPrefix("http") { return icon }
        return baseURL + icon
    }
    
    private static func deriveNameFromURL(_ url: URL) -> String {
        let comps = url.pathComponents.filter { $0 != "/" }
        if comps.count >= 2 {
            return comps[1].replacingOccurrences(of: "-", with: " ")
        }
        return url.deletingPathExtension().lastPathComponent
    }
    
    // MARK: - Fetch index (list sub-repos)
    
    func fetchIndexedRepos(from repo: ThemeRepository) async {
        isLoading = true
        errorMessage = nil
        indexedRepositories = []
        selectedRepository = repo
        
        guard let url = repo.jsonURL else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let repos = try JSONDecoder().decode([IndexedRepository].self, from: data)
            indexedRepositories = repos
        } catch {
            errorMessage = "Failed to load repos: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    // MARK: - Fetch themes từ top-level direct repo
    
    func fetchThemes(from repo: ThemeRepository) async {
        isLoading = true
        errorMessage = nil
        remoteThemes = []
        selectedRepository = repo
        selectedIndexedRepo = nil
        
        guard let url = repo.jsonURL else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let baseURL = url.deletingLastPathComponent().absoluteString
            
            if let repoJSON = try? JSONDecoder().decode(RepoJSONCodable.self, from: data) {
                let themes = repoJSON.themes ?? repoJSON.packages ?? []
                remoteThemes = themes.map { t in
                    RemoteTheme(name: t.name, description: t.description ?? "",
                                url: t.url, preview: t.preview,
                                authors: t.authors ?? "Unknown", baseURL: baseURL)
                }
            } else if let themes = try? JSONDecoder().decode([RemoteThemeCodable].self, from: data) {
                remoteThemes = themes.map { t in
                    RemoteTheme(name: t.name, description: t.description ?? "",
                                url: t.url, preview: t.preview,
                                authors: t.authors ?? "Unknown", baseURL: baseURL)
                }
            } else {
                errorMessage = "Invalid themes JSON"
            }
        } catch {
            errorMessage = "Failed to load themes: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    // MARK: - Fetch themes từ indexed sub-repo
    
    func fetchThemes(from indexed: IndexedRepository) async {
        isLoading = true
        errorMessage = nil
        remoteThemes = []
        selectedIndexedRepo = indexed
        
        guard let url = indexed.themesJSONURL else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let baseURL = indexed.cleanBaseURL
            
            if let repoJSON = try? JSONDecoder().decode(RepoJSONCodable.self, from: data) {
                let themes = repoJSON.themes ?? repoJSON.packages ?? []
                remoteThemes = themes.map { t in
                    RemoteTheme(name: t.name, description: t.description ?? "",
                                url: t.url, preview: t.preview,
                                authors: t.authors ?? "Unknown", baseURL: baseURL)
                }
            } else if let themes = try? JSONDecoder().decode([RemoteThemeCodable].self, from: data) {
                remoteThemes = themes.map { t in
                    RemoteTheme(name: t.name, description: t.description ?? "",
                                url: t.url, preview: t.preview,
                                authors: t.authors ?? "Unknown", baseURL: baseURL)
                }
            } else {
                errorMessage = "Invalid themes JSON"
            }
        } catch {
            errorMessage = "Failed to load themes: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    // MARK: - Back navigation
    
    func backToRepositories() {
        selectedRepository = nil
        selectedIndexedRepo = nil
        indexedRepositories = []
        remoteThemes = []
        errorMessage = nil
    }
    
    func backToIndexedRepos() {
        selectedIndexedRepo = nil
        remoteThemes = []
        errorMessage = nil
    }
    
    // MARK: - Download & Import
    
    func downloadAndImportTheme(_ theme: RemoteTheme, themeStore: PasscodeThemeStore) async throws {
        guard let downloadURL = theme.fullURL else { throw ThemeStoreError.invalidURL }
        downloadingThemes.insert(theme.id)
        defer { downloadingThemes.remove(theme.id) }
        
        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        let permanentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("passthm")
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
        do {
            try FileManager.default.unzipItem(at: sourceURL, to: themeFolder)
        } catch {
            try? FileManager.default.removeItem(at: themeFolder)
            throw ThemeStoreError.unzipFailed
        }
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
            try? fm.moveItem(at: teleURL.appendingPathComponent(filename),
                             to: themeFolder.appendingPathComponent(filename))
        }
        try? fm.removeItem(at: teleURL)
    }
}

// MARK: - Errors

enum ThemeStoreError: LocalizedError {
    case invalidURL
    case unzipFailed
    case invalidJSON
    case duplicateRepo
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:    return "URL không hợp lệ"
        case .unzipFailed:   return "Không giải nén được theme"
        case .invalidJSON:   return "File JSON không đúng định dạng (không nhận diện được repo)"
        case .duplicateRepo: return "Repo này đã có trong danh sách"
        }
    }
}