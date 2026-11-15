import Foundation
import ZIPFoundation

struct ThemeRepository: Codable, Identifiable {
    let url: String
    var name: String
    var iconURL: String?
    var parentIndex: String?
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

    // ⚡ FIX: handle absolute URL + leading "/"
    var fullURL: URL? {
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return URL(string: url)
        }
        let clean = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        let relPath = url.hasPrefix("/") ? String(url.dropFirst()) : url
        return URL(string: clean + relPath)
    }

    var previewURL: URL? {
        if preview.hasPrefix("http://") || preview.hasPrefix("https://") {
            return URL(string: preview)
        }
        let clean = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        let relPath = preview.hasPrefix("/") ? String(preview.dropFirst()) : preview
        return URL(string: clean + relPath)
    }
}

@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var repositories: [ThemeRepository] = []
    @Published var remoteThemes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var downloadingThemes: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]   // ⚡ NEW: progress %
    @Published var selectedRepository: ThemeRepository?

    private static let defaultRepoURL = "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde-Repository/main/themes.json"
    private static let defaultRepoName = "EnsWilde Repository"
    private let savedReposKey = "enswilde.themeStoreRepos.v4"

    // ⚡ Session cấu hình cho download nhanh + timeout hợp lý
    private static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300      // 5 phút cho file lớn
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    init() {
        UserDefaults.standard.removeObject(forKey: "enswilde.themeStoreRepos.v2")
        UserDefaults.standard.removeObject(forKey: "enswilde.themeStoreRepos.v3")
        loadSavedRepos()
        if needsReset() {
            Task { await bootstrapDefault() }
        }
    }

    private func needsReset() -> Bool {
        if repositories.isEmpty { return true }
        let hasDefault = repositories.contains { $0.url == Self.defaultRepoURL }
        if !hasDefault { return true }
        if let defRepo = repositories.first(where: { $0.url == Self.defaultRepoURL }),
           defRepo.name != Self.defaultRepoName {
            return true
        }
        let hasLegacy = repositories.contains { repo in
            let u = repo.url.lowercased()
            let n = repo.name.lowercased()
            return u.contains("nugget") || u.contains("serstars") ||
                   u.contains("yangjiii") || u.contains("yangjii") ||
                   n.contains("nugget") || n.contains("yangjii") ||
                   n.contains("ls nguyen") || n.contains("lsnguyen")
        }
        return hasLegacy
    }

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

    private func bootstrapDefault() async {
        isLoading = true
        defer { isLoading = false }

        var kept: [ThemeRepository] = []
        for r in repositories {
            let u = r.url.lowercased()
            let n = r.name.lowercased()
            if u.contains("nugget") || u.contains("serstars") ||
               u.contains("yangjiii") || u.contains("yangjii") ||
               n.contains("nugget") || n.contains("yangjii") ||
               n.contains("ls nguyen") || n.contains("lsnguyen") { continue }
            if r.url == Self.defaultRepoURL { continue }
            kept.append(r)
        }

        let defaultRepo = ThemeRepository(
            url: Self.defaultRepoURL,
            name: Self.defaultRepoName,
            iconURL: nil,
            parentIndex: nil
        )
        repositories = [defaultRepo] + kept
        saveRepos()
    }

    func addRepo(urlString: String) async throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw ThemeStoreError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)

        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let array = json as? [[String: Any]],
               array.contains(where: { $0["themesURL"] != nil && $0["baseURL"] != nil }) {
                try await flattenIndex(urlString: trimmed, parentIndex: trimmed)
                return
            }
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

        struct Entry { let name: String; let base: String; let themes: String }
        let entries: [Entry] = array.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let base = dict["baseURL"] as? String,
                  let themes = dict["themesURL"] as? String else { return nil }
            return Entry(name: name, base: base, themes: themes)
        }

        let icons: [String?] = await withTaskGroup(of: (Int, String?).self, returning: [String?].self) { group in
            for (idx, e) in entries.enumerated() {
                group.addTask {
                    let icon = await Self.fetchIconFromSubRepo(themesURL: e.themes, baseURL: e.base)
                    return (idx, icon)
                }
            }
            var results = [String?](repeating: nil, count: entries.count)
            for await (idx, icon) in group { results[idx] = icon }
            return results
        }

        var newRepos: [ThemeRepository] = []
        newRepos.reserveCapacity(entries.count)
        for (idx, e) in entries.enumerated() {
            let finalName = (e.themes == Self.defaultRepoURL) ? Self.defaultRepoName : e.name
            newRepos.append(ThemeRepository(url: e.themes, name: finalName, iconURL: icons[idx], parentIndex: parentIndex))
        }
        for repo in newRepos {
            if !repositories.contains(where: { $0.url == repo.url }) {
                repositories.append(repo)
            }
        }
        saveRepos()
    }

    private nonisolated static func fetchIconFromSubRepo(themesURL: String, baseURL: String) async -> String? {
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
        if url.absoluteString == Self.defaultRepoURL {
            return ThemeRepository(
                url: Self.defaultRepoURL,
                name: Self.defaultRepoName,
                iconURL: nil,
                parentIndex: nil
            )
        }

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

    func removeRepo(_ repo: ThemeRepository) {
        if let parent = repo.parentIndex {
            repositories.removeAll { $0.parentIndex == parent }
        } else {
            repositories.removeAll { $0.id == repo.id }
        }
        saveRepos()
    }

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

    // MARK: - Download + Import ⚡ Retry + recursive extract
    func downloadAndImportTheme(_ theme: RemoteTheme, themeStore: PasscodeThemeStore) async throws {
        guard let downloadURL = theme.fullURL else { throw ThemeStoreError.invalidURL }
        downloadingThemes.insert(theme.id)
        downloadProgress[theme.id] = 0
        defer {
            downloadingThemes.remove(theme.id)
            downloadProgress.removeValue(forKey: theme.id)
        }

        var lastError: Error?
        var downloadedURL: URL?
        for attempt in 1...3 {
            do {
                let (url, response) = try await Self.downloadSession.download(from: downloadURL)

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw NSError(domain: "ThemeStore", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "Server trả HTTP \(http.statusCode)"])
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                if size < 1024 {
                    throw NSError(domain: "ThemeStore", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "File tải về quá nhỏ (\(size) bytes) — có thể là lỗi server."])
                }

                // 🔥 FIX: Copy file ra temp an toàn vì file từ URLSession có thể bị xoá bất cứ lúc nào
                let safeURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
                try? FileManager.default.removeItem(at: safeURL)
                try FileManager.default.copyItem(at: url, to: safeURL)

                downloadedURL = safeURL
                break
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }

        guard let srcURL = downloadedURL else {
            throw lastError ?? NSError(domain: "ThemeStore", code: -2,
                                       userInfo: [NSLocalizedDescriptionKey: "Download thất bại sau 3 lần."])
        }

        defer { try? FileManager.default.removeItem(at: srcURL) }
        try await importThemeDirectly(from: srcURL, name: theme.name, store: themeStore)
    }

    // ⚡ FIX: Đẩy việc giải nén ra Background Thread để không đơ UI
    private func importThemeDirectly(from sourceURL: URL, name: String, store: PasscodeThemeStore) async throws {
        let newTheme = PasscodeTheme(name: name)
        let folder = newTheme.themeFolderURL
        
        let finalTheme = try await Task.detached(priority: .userInitiated) { () -> PasscodeTheme in
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let detected = ThemeStoreManager.detectSizeFromZIPStatic(at: sourceURL)

            do {
                try FileManager.default.unzipItem(at: sourceURL, to: folder)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw ThemeStoreError.unzipFailed
            }

            do {
                try PasscodeThemeViewModel.extractImagesRecursively(themeFolder: folder)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw ThemeStoreError.unzipFailed
            }

            let hasImages = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
                .contains { f in
                    let ext = (f as NSString).pathExtension.lowercased()
                    return ext == "png" || ext == "jpg" || ext == "jpeg"
                } ?? false
            guard hasImages else {
                try? FileManager.default.removeItem(at: folder)
                throw NSError(domain: "ThemeStore", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "Theme không có ảnh nào sau khi giải nén."])
            }

            var t = newTheme
            t.detectedSize = detected
            if detected == .big { t.keySize = .big }
            return t
        }.value
        
        // Thêm vào Store ở Main Thread
        store.addTheme(finalTheme)
    }

    // 🔥 FIX: Thêm hàm static để chạy được ở Background Thread
    nonisolated private static func detectSizeFromZIPStatic(at zipURL: URL) -> PasscodeTheme.DetectedSize {
        do {
            let archive = try Archive(url: zipURL, accessMode: .read)
            var sawBig = false
            for e in archive {
                if e.path.hasSuffix("_small") { return .small }
                if e.path.hasSuffix("_big") { sawBig = true }
            }
            return sawBig ? .big : .unknown
        } catch { return .unknown }
    }

    // Giữ nguyên để tránh break code khác (deprecated)
    @available(*, deprecated, message: "Dùng PasscodeThemeViewModel.extractImagesRecursively")
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