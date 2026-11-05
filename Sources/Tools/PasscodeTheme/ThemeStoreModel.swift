import Foundation

// MARK: - Remote Theme Model (Fix Decode)
struct RemoteTheme: Identifiable, Codable {
    var id: String { url }
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String
    var baseURL: String = ""
    
    enum CodingKeys: String, CodingKey {
        case name, description, url, preview, authors
    }
    
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

// Model đại diện cho 1 Repo
struct ThemeRepo: Identifiable {
    var id: String { url }
    let url: String
    var themes: [RemoteTheme]
    
    var name: String {
        // Tự động lấy tên tác giả/repo từ URL cho đẹp
        let components = url.components(separatedBy: "/")
        if let index = components.firstIndex(of: "main"), index > 0 {
            return components[index - 1]
        }
        return URL(string: url)?.lastPathComponent ?? "Repository"
    }
}

@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var repos: [ThemeRepo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // SỬA LỖI: Thay @AppStorage bằng UserDefaults
    var savedRepos: String {
        get {
            UserDefaults.standard.string(forKey: "SavedThemeRepos") ?? "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/refs/heads/main/wallpapers-passthemes.json"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "SavedThemeRepos")
        }
    }

    func fetchThemes() async {
        isLoading = true
        errorMessage = nil
        repos = []

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
                var fetchedThemes = try JSONDecoder().decode([RemoteTheme].self, from: data)
                
                // Lấy base URL bằng cách bỏ phần đuôi file json
                let baseURL = repoURL.deletingLastPathComponent().absoluteString
                
                for i in 0..<fetchedThemes.count {
                    fetchedThemes[i].baseURL = baseURL
                }
                
                let repo = ThemeRepo(url: repoURLString, themes: fetchedThemes)
                fetchedRepos.append(repo)
            } catch {
                print("Failed to load repo \(repoURLString): \(error)")
            }
        }
        
        if fetchedRepos.isEmpty {
            errorMessage = "Không thể tải theme từ bất kỳ Repository nào."
        } else {
            self.repos = fetchedRepos
        }
        
        self.isLoading = false
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
}