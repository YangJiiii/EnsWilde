import Foundation

// MARK: - Remote Theme Model
struct RemoteTheme: Identifiable, Codable {
    var id: String { url }
    let name: String
    let description: String?
    let url: String
    let preview: String
    let authors: String
    var baseURL: String = ""
    var type: ThemeType = .unknown
    
    enum ThemeType: String, Codable {
        case passcode = "passcode"
        case wallet = "wallet"
        case unknown = "unknown"
    }
    
    enum CodingKeys: String, CodingKey {
        case name, description, url, preview, authors, type
    }
}

// MARK: - Theme Source Model
struct ThemeSource: Codable {
    let name: String
    let baseURL: String
    let themesURL: String
}

// MARK: - Theme Store Manager
@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var themes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Link index.json của Nugget store (Cowabun.ga)
    // Đây là link chuẩn dùng cho cả Wallet và Passcode
    private let indexURLs = [
        URL(string: "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-apple.json")!, // Passcode themes
        URL(string: "https://cowabun.ga/wallpapers/themes.json")! // Fallback
    ]

    func fetchThemes() async {
        isLoading = true
        errorMessage = nil
        themes = []

        do {
            var allThemes: [RemoteTheme] = []
            
            for indexURL in indexURLs {
                do {
                    let (data, _) = try await URLSession.shared.data(from: indexURL)
                    
                    // Thử decode như một mảng ThemeSource trước
                    if let sources = try? JSONDecoder().decode([ThemeSource].self, from: data) {
                        for source in sources {
                            guard let themesURL = URL(string: source.themesURL) else { continue }
                            let (themesData, _) = try await URLSession.shared.data(from: themesURL)
                            var fetchedThemes = try JSONDecoder().decode([RemoteTheme].self, from: themesData)
                            for i in 0..<fetchedThemes.count {
                                fetchedThemes[i].baseURL = source.baseURL
                                // Tự phân loại dựa trên URL hoặc tên
                                if fetchedThemes[i].url.hasSuffix(".passthm") {
                                    fetchedThemes[i].type = .passcode
                                } else if fetchedThemes[i].url.hasSuffix(".zip") {
                                    fetchedThemes[i].type = .wallet
                                }
                            }
                            allThemes.append(contentsOf: fetchedThemes)
                        }
                    } 
                    // Nếu không phải ThemeSource, thử decode trực tiếp như mảng RemoteTheme
                    else if let directThemes = try? JSONDecoder().decode([RemoteTheme].self, from: data) {
                        var parsedThemes = directThemes
                        for i in 0..<parsedThemes.count {
                            if parsedThemes[i].url.hasSuffix(".passthm") {
                                parsedThemes[i].type = .passcode
                            } else if parsedThemes[i].url.hasSuffix(".zip") {
                                parsedThemes[i].type = .wallet
                            }
                        }
                        allThemes.append(contentsOf: parsedThemes)
                    }
                } catch {
                    print("Failed to load from \(indexURL): \(error)")
                    continue
                }
            }
            
            if allThemes.isEmpty {
                throw NSError(domain: "ThemeStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tải được theme nào từ các nguồn."])
            }
            
            self.themes = allThemes
            self.isLoading = false
            
        } catch {
            self.errorMessage = "Failed to load themes: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}