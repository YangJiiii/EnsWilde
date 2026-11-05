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
                ProgressView("Loading...")
            } else if storeManager.repos.isEmpty {
                ContentUnavailableView("Trống", systemImage: "tray", description: Text("Ấn nút + để thêm Repo."))
            } else {
                List {
                    ForEach(storeManager.repos) { repo in
                        NavigationLink(destination: RepoDetailView(repo: repo, themeStore: themeStore, viewModel: viewModel)) {
                            HStack(spacing: 12) {
                                // Icon hoặc chữ cái đầu (đỏ nếu lỗi)
                                if let iconURL = repo.iconURL {
                                    AsyncImage(url: iconURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(8)
                                } else {
                                    Text(String(repo.name.prefix(1)).uppercased())
                                        .font(.title3.bold())
                                        .foregroundColor(repo.errorMessage != nil ? .red : .orange)
                                        .frame(width: 40, height: 40)
                                        .background((repo.errorMessage != nil ? Color.red : Color.orange).opacity(0.15))
                                        .cornerRadius(8)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.name).font(.headline)
                                    if repo.errorMessage != nil {
                                        Text("Repo lỗi")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = repo.url
                            } label: {
                                Label("Copy Link Raw", systemImage: "doc.on.doc")
                            }
                            
                            Button {
                                Task { await storeManager.fetchThemes() }
                            } label: {
                                Label("Làm mới nguồn", systemImage: "arrow.clockwise")
                            }
                            
                            Button(role: .destructive) {
                                storeManager.removeRepo(url: repo.url)
                                Task { await storeManager.fetchThemes() }
                            } label: {
                                Label("Xoá nguồn", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Nguồn")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddRepo = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("Thêm Repo", isPresented: $showAddRepo) {
            TextField("https://.../themes.json", text: $newRepoURL).textInputAutocapitalization(.never).keyboardType(.URL)
            Button("Huỷ", role: .cancel) { newRepoURL = "" }
            Button("Thêm") {
                storeManager.addRepo(url: newRepoURL)
                newRepoURL = ""
                Task { await storeManager.fetchThemes() }
            }
        }
        .task {
            if storeManager.repos.isEmpty { await storeManager.fetchThemes() }
        }
    }
}

// MARK: - RepoDetailView (Xử lý hiển thị lỗi khi ấn vào)
struct RepoDetailView: View {
    let repo: ThemeRepo
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel

    var body: some View {
        Group {
            // Nếu repo lỗi -> hiện màn hình báo lỗi
            if let error = repo.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.red)
                    
                    Text("Repo lỗi")
                        .font(.title2.bold())
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Text(repo.url)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if repo.themes.isEmpty {
                ContentUnavailableView("Không có theme", systemImage: "tray", description: Text("Repo này chưa có theme nào."))
            } else {
                List {
                    ForEach(repo.themes) { theme in
                        NavigationLink(destination: RemoteThemeDownloadView(remoteTheme: theme, themeStore: themeStore, viewModel: viewModel)) {
                            HStack(spacing: 12) {
                                AsyncImage(url: theme.fullPreviewURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 60, height: 60).cornerRadius(8)
                                
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
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - RemoteThemeDownloadView
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
            } placeholder: { ProgressView() }.frame(height: 200).cornerRadius(12)
            
            Text(remoteTheme.name).font(.title2.bold())
            Text(remoteTheme.description ?? "").foregroundStyle(.secondary)
            
            if let errorMessage = errorMessage { Text(errorMessage).foregroundStyle(.red) }
            
            if isDownloading {
                ProgressView("Downloading & Importing...")
            } else {
                Button("Tải & Import Theme") { Task { await downloadAndImport() } }.buttonStyle(.borderedProminent)
            }
        }.padding().navigationTitle("Chi tiết").navigationBarTitleDisplayMode(.inline)
    }
    
    private func downloadAndImport() async {
        isDownloading = true; errorMessage = nil
        do {
            guard let url = remoteTheme.fullDownloadURL else { throw PasscodeThemeError.invalidFormat }
            let (data, _) = try await URLSession.shared.data(from: url)
            let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
            try data.write(to: tempFileURL)
            try await viewModel.importTheme(from: tempFileURL, name: remoteTheme.name)
            try? FileManager.default.removeItem(at: tempFileURL)
            dismiss()
        } catch { errorMessage = "Lỗi: \(error.localizedDescription)" }
        isDownloading = false
    }
}