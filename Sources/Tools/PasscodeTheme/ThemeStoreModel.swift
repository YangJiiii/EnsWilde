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
    
    // FIX: Tự động handle data thiếu
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

// MARK: - Theme Store Manager
@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var themes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let indexURL = URL(string: "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/refs/heads/main/wallpapers-passthemes.json")!
    private let baseRepoURL = "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/refs/heads/main/"

    func fetchThemes() async {
        isLoading = true
        errorMessage = nil
        themes = []

        do {
            let (data, _) = try await URLSession.shared.data(from: indexURL)
            var fetchedThemes = try JSONDecoder().decode([RemoteTheme].self, from: data)
            
            for i in 0..<fetchedThemes.count {
                fetchedThemes[i].baseURL = baseRepoURL
            }
            
            fetchedThemes.sort { a, b in
                let aIsWallet = a.name.localizedCaseInsensitiveContains("wallet") || (a.description?.localizedCaseInsensitiveContains("wallet") ?? false)
                let bIsWallet = b.name.localizedCaseInsensitiveContains("wallet") || (b.description?.localizedCaseInsensitiveContains("wallet") ?? false)
                if aIsWallet && !bIsWallet { return true }
                if !aIsWallet && bIsWallet { return false }
                return false
            }
            
            self.themes = fetchedThemes
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load themes: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}