import Foundation

// MARK: - Định dạng Theme chung (Map từ cả JSON cũ và mới)
struct RemoteTheme: Identifiable, Decodable {
    var id: String { url }
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String
    var baseURL: String = ""
    
    enum CodingKeys: String, CodingKey {
        case name, description, url, preview, authors
        // Keys cho JSON mới (3105 style)
        case summary, author, download, icon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Hỗ trợ cả tên cũ và tên mới
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Theme"
        
        // JSON cũ dùng description, JSON mới dùng summary
        description = try container.decodeIfPresent(String.self, forKey: .description) 
                   ?? container.decodeIfPresent(String.self, forKey: .summary)
        
        // JSON cũ dùng url, JSON mới dùng download
        url = try container.decodeIfPresent(String.self, forKey: .url) 
           ?? container.decodeIfPresent(String.self, forKey: .download) ?? ""
        
        // JSON cũ dùng preview, JSON mới dùng icon
        preview = try container.decodeIfPresent(String.self, forKey: .preview) 
               ?? container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        
        // JSON cũ dùng authors, JSON mới dùng author
        authors = try container.decodeIfPresent(String.self, forKey: .authors) 
               ?? container.decodeIfPresent(String.self, forKey: .author) ?? "Unknown Author"
    }
    
    var fullDownloadURL: URL? { URL(string: baseURL + url) }
    var fullPreviewURL: URL? { URL(string: baseURL + preview) }
}

// MARK: - Định dạng Repo chung
struct RepoJSON: Decodable {
    let name: String?
    let description: String?
    let icon: String?
    let themes: [RemoteTheme]?      // Dạng cũ 1
    let packages: [RemoteTheme]?    // Dạng mới (3105)
}

struct ThemeRepo: Identifiable {
    var id: String { url }
    let url: String
    let name: String
    let iconURL: URL?
    var themes: [RemoteTheme]
    var errorMessage: String?
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
        isLoading = true
        repos = []
        
        let repoURLs = savedRepos.components(separatedBy: ",").compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !repoURLs.isEmpty else { isLoading = false; return }

        var fetchedRepos: [ThemeRepo] = []
        
        for repoURLString in repoURLs {
            guard let repoURL = URL(string: repoURLString) else { continue }
            let repoName = getRepoNameFromURL(repoURL)
            let baseURL = repoURL.deletingLastPathComponent().absoluteString
            
            do {
                let (data, _) = try await URLSession.shared.data(from: repoURL)
                
                // 1. Thử decode dạng Object bọc (Chứa themes hoặc packages)
                if let repoJSON = try? JSONDecoder().decode(RepoJSON.self, from: data) {
                    let rawThemes = repoJSON.themes ?? repoJSON.packages ?? []
                    var themes = rawThemes
                    for i in 0..<themes.count { themes[i].baseURL = baseURL }
                    
                    var iconURL: URL?
                    if let icon = repoJSON.icon {
                        iconURL = icon.hasPrefix("http") ? URL(string: icon) : URL(string: baseURL + icon)
                    }
                    
                    let finalName = repoJSON.name ?? repoName
                    fetchedRepos.append(ThemeRepo(url: repoURLString, name: finalName, iconURL: iconURL, themes: themes, errorMessage: nil))
                }
                // 2. Thử decode dạng Array thuần túy
                else if var themes = try? JSONDecoder().decode([RemoteTheme].self, from: data) {
                    for i in 0..<themes.count { themes[i].baseURL = baseURL }
                    fetchedRepos.append(ThemeRepo(url: repoURLString, name: repoName, iconURL: nil, themes: themes, errorMessage: nil))
                }
                // 3. Lỗi JSON
                else {
                    fetchedRepos.append(ThemeRepo(
                        url: repoURLString,
                        name: repoName,
                        iconURL: nil,
                        themes: [],
                        errorMessage: "Tệp mô tả kho không hợp lệ hoặc quá lớn."
                    ))
                }
            } catch {
                fetchedRepos.append(ThemeRepo(
                    url: repoURLString,
                    name: repoName,
                    iconURL: nil,
                    themes: [],
                    errorMessage: "Không thể kết nối tới máy chủ."
                ))
            }
        }
        
        self.repos = fetchedRepos
        isLoading = false
    }
    
    private func getRepoNameFromURL(_ url: URL) -> String {
        let components = url.pathComponents.filter { $0 != "/" }
        if components.count >= 2 {
            return components[1].replacingOccurrences(of: "-", with: " ")
        }
        return url.deletingPathExtension().lastPathComponent
    }
    
    func addRepo(url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var reposList = savedRepos.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !reposList.contains(trimmed) {
            reposList.append(trimmed)
            savedRepos = reposList.joined(separator: ",")
        }
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
}