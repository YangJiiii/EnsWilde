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
}

// MARK: - Theme Store Manager
@MainActor
class ThemeStoreManager: ObservableObject {
    @Published var themes: [RemoteTheme] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // FIX: Sửa lại cái URL bị sai cú pháp và sửa lại username cho đúng
    private let indexURL = URL(string: "https://raw.githubusercontent.com/nguyenls3005-cell/EnsWilde/main/themes-storeview/index.json")!

    func fetchThemes() async {
        isLoading = true
        errorMessage = nil
        themes = []

        do {
            let (data, _) = try await URLSession.shared.data(from: indexURL)
            let sources = try JSONDecoder().decode([ThemeSource].self, from: data)
            
            var allThemes: [RemoteTheme] = []
            
            for source in sources {
                guard let themesURL = URL(string: source.themesURL) else { continue }
                let (themesData, _) = try await URLSession.shared.data(from: themesURL)
                
                var fetchedThemes = try JSONDecoder().decode([RemoteTheme].self, from: themesData)
                
                for i in 0..<fetchedThemes.count {
                    fetchedThemes[i].baseURL = source.baseURL
                }
                
                allThemes.append(contentsOf: fetchedThemes)
            }
            
            // FIX: Tự động sort đẩy mấy cái tên/desc có chữ "Wallet" lên đầu
            allThemes.sort { a, b in
                let aIsWallet = a.name.localizedCaseInsensitiveContains("wallet") || (a.description?.localizedCaseInsensitiveContains("wallet") ?? false)
                let bIsWallet = b.name.localizedCaseInsensitiveContains("wallet") || (b.description?.localizedCaseInsensitiveContains("wallet") ?? false)
                
                if aIsWallet && !bIsWallet { return true }
                if !aIsWallet && bIsWallet { return false }
                return false
            }
            
            self.themes = allThemes
            self.isLoading = false
            
        } catch {
            self.errorMessage = "Failed to load themes: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}

// MARK: - Theme Source Model
struct ThemeSource: Codable {
    let name: String
    let baseURL: String
    let themesURL: String
}