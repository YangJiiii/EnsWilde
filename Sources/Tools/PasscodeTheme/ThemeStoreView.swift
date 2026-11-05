import SwiftUI

struct ThemeStoreView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @StateObject private var storeManager = ThemeStoreManager()
    
    @StateObject private var viewModel: PasscodeThemeViewModel
    
    @State private var showAddRepo = false
    @State private var newRepoURL = ""
    
    init(themeStore: PasscodeThemeStore) {
        self.themeStore = themeStore
        _viewModel = StateObject(wrappedValue: PasscodeThemeViewModel(store: themeStore))
    }

    var body: some View {
        Group {
            if storeManager.isLoading {
                ProgressView("Loading Repos...")
            } else if let error = storeManager.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await storeManager.fetchThemes() }
                    }
                }
                .padding()
            } else if storeManager.repos.isEmpty {
                ContentUnavailableView("No Repositories", systemImage: "folder.badge.plus", description: Text("Add a repository by clicking the + button."))
            } else {
                List {
                    // Hiển thị từng Repo thành 1 Section
                    ForEach(storeManager.repos) { repo in
                        Section(header: Text(repo.name).font(.headline)) {
                            ForEach(repo.themes) { theme in
                                NavigationLink(destination: RemoteThemeDownloadView(remoteTheme: theme, themeStore: themeStore, viewModel: viewModel)) {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: theme.fullPreviewURL) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Color.gray.opacity(0.3)
                                        }
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(theme.name).font(.headline)
                                            Text(theme.authors).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Theme Store")
        .toolbar {
            // Nút + góc trên bên phải
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddRepo = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Add Repository", isPresented: $showAddRepo) {
            TextField("https://.../themes.json", text: $newRepoURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("Cancel", role: .cancel) { newRepoURL = "" }
            Button("Add") {
                storeManager.addRepo(url: newRepoURL)
                newRepoURL = ""
                Task { await storeManager.fetchThemes() }
            }
        } message: {
            Text("Nhập URL trực tiếp đến file JSON chứa danh sách theme.")
        }
        .task {
            if storeManager.repos.isEmpty {
                await storeManager.fetchThemes()
            }
        }
    }
}

struct RemoteThemeDownloadView: View {
    let remoteTheme: RemoteTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var isDownloading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            AsyncImage(url: remoteTheme.fullPreviewURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView()
            }
            .frame(height: 200)
            .cornerRadius(12)
            
            Text(remoteTheme.name).font(.title2.bold())
            Text(remoteTheme.description ?? "").foregroundStyle(.secondary)
            
            if let errorMessage = errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            
            if isDownloading {
                ProgressView("Downloading and Importing...")
            } else {
                Button("Download & Import Theme") {
                    Task {
                        await downloadAndImport()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .navigationTitle("Theme Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func downloadAndImport() async {
        isDownloading = true
        errorMessage = nil
        
        do {
            guard let url = remoteTheme.fullDownloadURL else {
                throw PasscodeThemeError.invalidFormat
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
            try data.write(to: tempFileURL)
            
            try await viewModel.importTheme(from: tempFileURL, name: remoteTheme.name)
            
            try? FileManager.default.removeItem(at: tempFileURL)
            dismiss()
            
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }
        
        isDownloading = false
    }
}