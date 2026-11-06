import SwiftUI

// MARK: - Giao diện Danh sách Nguồn (Ảnh 1)
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
                ProgressView("Đang tải...")
            } else if storeManager.repos.isEmpty {
                ContentUnavailableView("Trống", systemImage: "tray", description: Text("Ấn nút + để thêm Nguồn."))
            } else {
                List {
                    ForEach(storeManager.repos) { repo in
                        NavigationLink(destination: RepoDetailView(repo: repo, themeStore: themeStore, viewModel: viewModel)) {
                            RepoRowView(repo: repo)
                        }
                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                        .contextMenu {
                            Button { UIPasteboard.general.string = repo.url } label: { Label("Copy Link Raw", systemImage: "doc.on.doc") }
                            Button { Task { await storeManager.fetchThemes() } } label: { Label("Làm mới nguồn", systemImage: "arrow.clockwise") }
                            Button(role: .destructive) { storeManager.removeRepo(url: repo.url) } label: { Label("Xoá nguồn", systemImage: "trash") }
                        }
                    }
                    .onDelete { storeManager.removeRepo(at: $0) }
                }
                .listStyle(.insetGrouped)
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

// MARK: - Repo Row (Hiển thị trong danh sách)
struct RepoRowView: View {
    let repo: ThemeRepo
    
    var body: some View {
        HStack(spacing: 12) {
            if let iconURL = repo.iconURL {
                AsyncImage(url: iconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 44, height: 44)
                .cornerRadius(8)
            } else {
                Text(String(repo.name.prefix(1)).uppercased())
                    .font(.title3.bold())
                    .foregroundColor(repo.errorMessage != nil ? .red : .orange)
                    .frame(width: 44, height: 44)
                    .background((repo.errorMessage != nil ? Color.red : Color.orange).opacity(0.15))
                    .cornerRadius(8)
            }
            
            Text(repo.name).font(.headline)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Giao diện Chi tiết Nguồn (Ảnh 2 & 4)
struct RepoDetailView: View {
    let repo: ThemeRepo
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel

    var body: some View {
        List {
            // Header: Icon, Tên, Mô tả hoặc Lỗi
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        if let iconURL = repo.iconURL {
                            AsyncImage(url: iconURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 60, height: 60)
                            .cornerRadius(12)
                        } else {
                            Text(String(repo.name.prefix(1)).uppercased())
                                .font(.title.bold())
                                .foregroundColor(repo.errorMessage != nil ? .red : .orange)
                                .frame(width: 60, height: 60)
                                .background((repo.errorMessage != nil ? Color.red : Color.orange).opacity(0.15))
                                .cornerRadius(12)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(repo.name)
                                .font(.title3.bold())
                            
                            if let error = repo.errorMessage {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.red)
                                }
                            } else {
                                if let desc = repo.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(repo.themes.count) gói")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            
            // Phần Tag (Nếu không lỗi)
            if repo.errorMessage == nil {
                if repo.themes.isEmpty {
                    Section {
                        Text("Nguồn này chưa có gói khả dụng. Hãy bật hoặc làm mới nguồn rồi thử lại.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    Section(header: Text("Tag").font(.headline).foregroundStyle(.white).textCase(nil)) {
                        ForEach(repo.groupedTags, id: \.name) { tag in
                            NavigationLink(destination: PackageListView(repo: repo, tagName: tag.name, themeStore: themeStore, viewModel: viewModel)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.orange)
                                        .font(.title3)
                                        .frame(width: 32, height: 32)
                                        .background(Color.orange.opacity(0.15))
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tag.name).font(.body)
                                        Text("\(tag.count) gói").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                }
            } else {
                // Box cảnh báo nếu có lỗi
                Section {
                    Text("Nguồn này chưa có gói khả dụng. Hãy bật hoặc làm mới nguồn rồi thử lại.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Danh sách Package theo Tag
struct PackageListView: View {
    let repo: ThemeRepo
    let tagName: String
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel

    var filteredThemes: [RemoteTheme] {
        if tagName == "Tất cả gói" { return repo.themes }
        return repo.themes.filter { theme in
            theme.category == tagName || (theme.tags?.contains(tagName) ?? false)
        }
    }

    var body: some View {
        List(filteredThemes) { theme in
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
                .padding(.vertical, 4)
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .listStyle(.insetGrouped)
        .navigationTitle(tagName)
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
            } placeholder: { ProgressView() }
            .frame(height: 200)
            .cornerRadius(12)
            
            Text(remoteTheme.name).font(.title2.bold())
            Text(remoteTheme.description ?? "").foregroundStyle(.secondary)
            
            if let errorMessage = errorMessage { Text(errorMessage).foregroundStyle(.red) }
            
            if isDownloading {
                ProgressView("Đang tải & Import...")
            } else {
                Button("Tải & Import") { Task { await downloadAndImport() } }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .navigationTitle("Chi tiết")
        .navigationBarTitleDisplayMode(.inline)
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