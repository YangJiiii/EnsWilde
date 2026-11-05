import Foundation

struct RemoteTheme: Identifiable, Codable {
    var id: String { url }
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String
    var baseURL: String = ""
    
    enum CodingKeys: String, CodingKey { case name, description, url, preview, authors }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Theme"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        url = try container.decode(String.self, forKey: .url)
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? ""
        authors = try container.decodeIfPresent(String.self, forKey: .authors) ?? "Unknown Author"
    }
    
    var fullDownloadURL: URL? { URL(string: baseURL + url) }
    var fullPreviewURL: URL? { URL(string: baseURL + preview) }
}

// Cấu trúc JSON mới (hỗ trợ name, icon, themes)
struct RepoJSON: Codable {
    let name: String?
    let icon: String?
    let themes: [RemoteTheme]
}

struct ThemeRepo: Identifiable {
    var id: String { url }
    let url: String
    let name: String
    let iconURL: URL?
    var themes: [RemoteTheme]
}

@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var repos: [ThemeRepo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    var savedRepos: String {
        get { UserDefaults.standard.string(forKey: "SavedThemeRepos") ?? "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/refs/heads/main/wallpapers-passthemes.json" }
        set { UserDefaults.standard.set(newValue, forKey: "SavedThemeRepos") }
    }

    func fetchThemes() async {
        isLoading = true; errorMessage = nil; repos = []
        let repoURLs = savedRepos.components(separatedBy: ",").compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        guard !repoURLs.isEmpty else {
            errorMessage = "Chưa có Repository nào được thêm."
            isLoading = false
            return
        }

        var fetchedRepos: [ThemeRepo] = []
        for repoURLString in repoURLs {
            guard let repoURL = URL(string: repoURLString) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: repoURL)
                let baseURL = repoURL.deletingLastPathComponent().absoluteString
                
                // Thử decode dạng mới (có object bọc)
                if let repoJSON = try? JSONDecoder().decode(RepoJSON.self, from: data) {
                    var themes = repoJSON.themes
                    for i in 0..<themes.count { themes[i].baseURL = baseURL }
                    
                    let iconURL: URL?
                    if let icon = repoJSON.icon {
                        // Nếu icon là link tuyệt đối thì dùng luôn, nếu là path thì ghép với baseURL
                        if icon.hasPrefix("http") {
                            iconURL = URL(string: icon)
                        } else {
                            iconURL = URL(string: baseURL + icon)
                        }
                    } else {
                        iconURL = nil
                    }
                    
                    let repoName = repoJSON.name ?? getRepoNameFromURL(repoURL)
                    fetchedRepos.append(ThemeRepo(url: repoURLString, name: repoName, iconURL: iconURL, themes: themes))
                } 
                // Thử decode dạng cũ (array thuần túy)
                else if var themes = try? JSONDecoder().decode([RemoteTheme].self, from: data) {
                    for i in 0..<themes.count { themes[i].baseURL = baseURL }
                    let repoName = getRepoNameFromURL(repoURL)
                    fetchedRepos.append(ThemeRepo(url: repoURLString, name: repoName, iconURL: nil, themes: themes))
                } 
                else {
                    print("Cannot decode repo: \(repoURLString)")
                }
            } catch {
                print("Failed to load repo \(repoURLString): \(error)")
            }
        }
        
        if fetchedRepos.isEmpty {
            self.errorMessage = "Không thể tải theme. Vui lòng kiểm tra lại URL hoặc mạng."
        } else {
            self.repos = fetchedRepos
        }
        isLoading = false
    }
    
    // Hàm lấy tên Repo (bỏ tên user)
    private func getRepoNameFromURL(_ url: URL) -> String {
        let components = url.pathComponents.filter { $0 != "/" }
        // URL: https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde-Repository/main/themes.json
        // components: ["nguyenls3005-cell", "EnsWilde-Repository", "main", "themes.json"]
        // Lấy phần tử index 1 là tên Repo
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
    
    func removeRepo(url: String) {
        var reposList = savedRepos.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        reposList.removeAll { $0 == url }
        savedRepos = reposList.joined(separator: ",")
    }
}