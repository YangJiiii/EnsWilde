import Foundation
import ZIPFoundation

struct ThemeRepository: Codable, Identifiable {
    let url: String              // themesJSONURL
    var name: String
    var iconURL: String?
    var parentIndex: String?     // URL index gốc nếu được flatten (để xoá theo nhóm)
    var id: String { url }
    var jsonURL: URL? { URL(string: url) }
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

@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var repositories: [ThemeRepository] = []
    @Published var remoteThemes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var downloadingThemes: Set<String> = []
    @Published var selectedRepository: ThemeRepository?

    // 🎯 Repo mặc định DUY NHẤT — trỏ thẳng tới themes.json của bạn
    private static let defaultRepoURL = "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde-Repository/main/themes.json"
    private static let defaultRepoName = "LS Nguyen - EnsWilde Themes"

    // 🔄 Bump v2 → v3: reset toàn bộ cache cũ (2 repo Nugget + YangJiii sẽ bị xoá)
    private let savedReposKey = "enswilde.themeStoreRepos.v3"

    init() {
        loadSavedRepos()
        if needsReset() {
            Task { await bootstrapDefault() }
        }
    }

    // Kiểm tra xem có cần reset về repo mặc định không
    private func needsReset() -> Bool {
        // 1. Chưa có repo nào → cần khởi tạo
        if repositories.isEmpty { return true }

        // 2. Không chứa repo mặc định của mình → cần thêm
        let hasDefault = repositories.contains { $0.url == Self.defaultRepoURL }
        if !hasDefault { return true }

        // 3. Còn sót repo legacy (Nugget / YangJiii / SerStars) → cần xoá
        let hasLegacy = repositories.contains { repo in
            let u = repo.url.lowercased()
            let n = repo.name.lowercased()
            return u.contains("nugget") || u.contains("serstars") ||
                   u.contains("yangjiii") || u.contains("yangjii") ||
                   n.contains("nugget") || n.contains("yangjii")
        }
        if hasLegacy { return true }

        return false
    }

    // MARK: - Persistence

    private func loadSavedRepos() {
        if let data = UserDefaults.standard.data(forKey: savedReposKey),
           let decoded = try? JSONDecoder().decode([ThemeRepository].self, from: data) {
            repositories = decoded
        }
    }

    private func saveRepos() {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: savedReposKey)
        }
    }

    // 🎯 Khởi tạo: hard-code đúng 1 repo duy nhất, KHÔNG tải index.json nữa
    private func bootstrapDefault() async {
        isLoading = true
        defer { isLoading = false }

        // Giữ lại các repo khác user đã add (trừ legacy), luôn đảm bảo có repo mặc định
        var kept: [ThemeRepository] = []
        for r in repositories {
            // Bỏ qua legacy
            let u = r.url.lowercased()
            let n = r.name.lowercased()
            if u.contains("nugget") || u.contains("serstars") ||
               u.contains("yangjiii") || u.contains("yangjii") ||
               n.contains("nugget") || n.contains("yangjii") {
                continue
            }
            // Bỏ qua nếu trùng URL mặc định (sẽ thêm lại bên dưới)
            if r.url == Self.defaultRepoURL { continue }
            kept.append(r)
        }

        // Thêm repo mặc định lên đầu
        let defaultRepo = ThemeRepository(
            url: Self.defaultRepoURL,
            name: Self.defaultRepoName,
            iconURL: nil,
            parentIndex: nil
        )
        repositories = [defaultRepo] + kept
        saveRepos()
    }

    // MARK: - Add Repo (vẫn giữ hỗ trợ add index / repo trực tiếp)

    func addRepo(urlString: String) async throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw ThemeStoreError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)

        if let json = try? JSONSerialization.jsonObject(with: data) {
            // Index format: [{name, baseURL, themesURL}]
            if let array = json as? [[String: Any]],
               array.contains(where: { $0["themesURL"] != nil && $0["baseURL"] != nil }) {
                try await flattenIndex(urlString: trimmed, parentIndex: trimmed)
                return
            }

            // Direct repo: {name, icon, themes|packages} hoặc [themes]
            let repo = try parseDirectRepo(url: url, data: data)
            if !repositories.contains(where: { $0.url == repo.url }) {
                repositories.append(repo)
                saveRepos()
            }
            return
        }
        throw ThemeStoreError.invalidJSON
    }

    private func flattenIndex(urlString: String, parentIndex: String) async throws {
        guard let url = URL(string: urlString) else { throw ThemeStoreError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ThemeStoreError.invalidJSON
        }

        var newRepos: [ThemeRepository] = []
        for dict in array {
            guard let name = dict["name"] as? String,
                  let base = dict["baseURL"] as? String,
                  let themes = dict["themesURL"] as? String else { continue }

            let iconURL = await fetchIconFromSubRepo(themesURL: themes, baseURL: base)

            newRepos.append(ThemeRepository(
                url: themes,
                name: name,
                iconURL: iconURL,
                parentIndex: parentIndex
            ))
        }

        for repo in newRepos {
            if !repositories.contains(where: { $0.url == repo.url }) {
                repositories.append(repo)
            }
        }
        saveRepos()
    }

    private func fetchIconFromSubRepo(themesURL: String, baseURL: String) async -> String? {
        guard let url = URL(string: themesURL) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let dict = json as? [String: Any], let iconStr = dict["icon"] as? String {
            let clean = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
            return iconStr.hasPrefix("http") ? iconStr : clean + iconStr
        }
        return nil
    }

    private func parseDirectRepo(url: URL, data: Data) throws -> ThemeRepository {
        let baseURLString = url.deletingLastPathComponent().absoluteString
        let defaultName = Self.deriveNameFromURL(url)

        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let name = dict["name"] as? String ?? defaultName
            var icon: String? = nil
            if let iconStr = dict["icon"] as? String {
                icon = iconStr.hasPrefix("http") ? iconStr : baseURLString + iconStr
            }
            return ThemeRepository(url: url.absoluteString, name: name, iconURL: icon, parentIndex: nil)
        }
        return ThemeRepository(url: url.absoluteString, name: defaultName, iconURL: nil, parentIndex: nil)
    }

    private static func deriveNameFromURL(_ url: URL) -> String {
        let comps = url.pathComponents.filter { $0 != "/" }
        if comps.count >= 2 { return comps[1].replacingOccurrences(of: "-", with: " ") }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Remove Repo (xử lý theo parentIndex)

    func removeRepo(_ repo: ThemeRepository) {
        if let parent = repo.parentIndex {
            repositories.removeAll { $0.parentIndex == parent }
        } else {
            repositories.removeAll { $0.id == repo.id }
        }
        saveRepos()
    }

    // MARK: - Fetch Themes

    func fetchThemes(from repo: ThemeRepository) async {
        isLoading = true; errorMessage = nil; remoteThemes = []; selectedRepository = repo

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

    func backToRepositories() {
        selectedRepository = nil
        remoteThemes = []
        errorMessage = nil
    }

    private func parseThemes(from data: Data, baseURL: String) throws -> [RemoteTheme] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

        var arr: [[String: Any]] = []
        if let a = json as? [[String: Any]] { arr = a }
        else if let d = json as? [String: Any] {
            if let t = d["themes"] as? [[String: Any]] { arr = t }
            else if let p = d["packages"] as? [[String: Any]] { arr = p }
        }

        return arr.compactMap { dict in
            let name = dict["name"] as? String ?? "Unknown"
            let desc = (dict["description"] as? String) ?? (dict["summary"] as? String) ?? ""
            let url = (dict["url"] as? String) ?? (dict["download"] as? String) ?? ""
            let preview = (dict["preview"] as? String) ?? (dict["icon"] as? String) ?? ""
            let authors = (dict["authors"] as? String) ?? (dict["author"] as? String) ?? "Unknown"
            guard !url.isEmpty else { return nil }
            return RemoteTheme(name: name, description: desc, url: url, preview: preview, authors: authors, baseURL: baseURL)
        }
    }

    // MARK: - Download

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
        let folder = newTheme.themeFolderURL
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let detected = detectSizeFromZIP(at: sourceURL)
        do { try FileManager.default.unzipItem(at: sourceURL, to: folder) }
        catch { try? FileManager.default.removeItem(at: folder); throw ThemeStoreError.unzipFailed }
        try extractImagesFromTelephonySubfolder(themeFolder: folder)
        var t = newTheme; t.detectedSize = detected
        store.addTheme(t)
    }

    private func detectSizeFromZIP(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            for e in archive { if e.path.hasSuffix("_small") { return .small } }
            for e in archive { if e.path.hasSuffix("_big") { return .big } }
            return .unknown
        } catch { return .unknown }
    }

    private func extractImagesFromTelephonySubfolder(themeFolder: URL) throws {
        let fm = FileManager.default
        guard let c = try? fm.contentsOfDirectory(atPath: themeFolder.path) else { return }
        guard let t = c.first(where: { $0.hasPrefix("Telephony") || $0.hasPrefix("TelephonyUI") }) else { return }
        let tURL = themeFolder.appendingPathComponent(t)
        guard let imgs = try? fm.contentsOfDirectory(atPath: tURL.path) else { return }
        for f in imgs {
            let ext = (f as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            try? fm.moveItem(at: tURL.appendingPathComponent(f), to: themeFolder.appendingPathComponent(f))
        }
        try? fm.removeItem(at: tURL)
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