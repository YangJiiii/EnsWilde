import Foundation

struct RemoteTheme: Identifiable, Decodable {
    var id: String { url }
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String
    let category: String?
    let tags: [String]?
    var baseURL: String = ""
    
    enum CodingKeys: String, CodingKey {
        case name, description, url, preview, authors, category, tags
        case summary, author, download, icon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Theme"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? container.decodeIfPresent(String.self, forKey: .summary)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? container.decodeIfPresent(String.self, forKey: .download) ?? ""
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        authors = try container.decodeIfPresent(String.self, forKey: .authors) ?? container.decodeIfPresent(String.self, forKey: .author) ?? "Unknown Author"
        category = try container.decodeIfPresent(String.self, forKey: .category)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
    }
    
    var fullDownloadURL: URL? { URL(string: baseURL + url) }
    var fullPreviewURL: URL? { URL(string: baseURL + preview) }
}

struct RepoJSON: Decodable {
    let name: String?
    let description: String?
    let icon: String?
    let themes: [RemoteTheme]?
    let packages: [RemoteTheme]?
}

struct ThemeRepo: Identifiable {
    var id: String { url }
    let url: String
    let name: String
    let description: String?
    let iconURL: URL?
    var themes: [RemoteTheme]
    var errorMessage: String?
    
    var groupedTags: [(name: String, count: Int)] {
        var counts: [String: Int] = ["Tất cả gói": themes.count]
        for theme in themes {
            if let cat = theme.category, !cat.isEmpty { counts[cat, default: 0] += 1 }
            if let tags = theme.tags {
                for tag in tags where !tag.isEmpty { counts[tag, default: 0] += 1 }
            }
        }
        return counts.map { (name: $0.key, count: $0.value) }.sorted {
            if $0.name == "Tất cả gói" { return true }
            if $1.name == "Tất cả gói" { return false }
            return $0.count > $1.count
        }
    }
}

@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var repos: [ThemeRepo] = []
    @Published var isLoading = false
    
    var savedRepos: String {
        get { UserDefaults.standard.string(forKey: "SavedThemeRepos") ?? "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/refs/heads/main/wallpapers-passthemes.json" }
        set { UserDefaults.standard.set(newValue, forKey: "SavedThemeRepos") }
    }

    func fetchThemes() async {
        isLoading = true; repos = []
        let repoURLs = savedRepos.components(separatedBy: ",").compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !repoURLs.isEmpty else { isLoading = false; return }

        var fetchedRepos: [ThemeRepo] = []
        for repoURLString in repoURLs {
            guard let repoURL = URL(string: repoURLString) else { continue }
            let repoName = getRepoNameFromURL(repoURL)
            let baseURL = repoURL.deletingLastPathComponent().absoluteString
            
            do {
                let (data, _) = try await URLSession.shared.data(from: repoURL)
                if let repoJSON = try? JSONDecoder().decode(RepoJSON.self, from: data) {
                    let rawThemes = repoJSON.themes ?? repoJSON.packages ?? []
                    var themes = rawThemes
                    for i in 0..<themes.count { themes[i].baseURL = baseURL }
                    var iconURL: URL?
                    if let icon = repoJSON.icon { iconURL = icon.hasPrefix("http") ? URL(string: icon) : URL(string: baseURL + icon) }
                    fetchedRepos.append(ThemeRepo(url: repoURLString, name: repoJSON.name ?? repoName, description: repoJSON.description, iconURL: iconURL, themes: themes, errorMessage: nil))
                } else if var themes = try? JSONDecoder().decode([RemoteTheme].self, from: data) {
                    for i in 0..<themes.count { themes[i].baseURL = baseURL }
                    fetchedRepos.append(ThemeRepo(url: repoURLString, name: repoName, description: nil, iconURL: nil, themes: themes, errorMessage: nil))
                } else {
                    fetchedRepos.append(ThemeRepo(url: repoURLString, name: repoName, description: nil, iconURL: nil, themes: [], errorMessage: "Tệp mô tả kho không hợp lệ hoặc quá lớn."))
                }
            } catch {
                fetchedRepos.append(ThemeRepo(url: repoURLString, name: repoName, description: nil, iconURL: nil, themes: [], errorMessage: "Không thể kết nối tới máy chủ."))
            }
        }
        self.repos = fetchedRepos
        isLoading = false
    }
    
    private func getRepoNameFromURL(_ url: URL) -> String {
        let components = url.pathComponents.filter { $0 != "/" }
        if components.count >= 2 { return components[1].replacingOccurrences(of: "-", with: " ") }
        return url.deletingPathExtension().lastPathComponent
    }
    
    func addRepo(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var reposList = savedRepos.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !reposList.contains(trimmed) { reposList.append(trimmed); savedRepos = reposList.joined(separator: ",") }
    }
    
    func removeRepo(at offsets: IndexSet) {
        for index in offsets {
            let repoUrl = repos[index].url
            var reposList = savedRepos.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            reposList.removeAll { $0 == repoUrl }
            savedRepos = reposList.joined(separator: ",")
        }
        Task { await fetchThemes() }
    }
    
    func removeRepo(url: String) {
        var reposList = savedRepos.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        reposList.removeAll { $0 == url }
        savedRepos = reposList.joined(separator: ",")
        Task { await fetchThemes() }
    }
}