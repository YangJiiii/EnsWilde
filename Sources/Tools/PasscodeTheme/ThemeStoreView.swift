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
                                if let iconURL = repo.iconURL {
                                    AsyncImage(url: iconURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(8)
                                } else {
                                    // Icon chữ cái
                                    Text(String(repo.name.prefix(1)).uppercased())
                                        .font(.title3.bold())
                                        .foregroundColor(repo.errorMessage != nil ? .red : .orange)
                                        .frame(width: 40, height: 40)
                                        .background((repo.errorMessage != nil ? Color.red : Color.orange).opacity(0.15))
                                        .cornerRadius(8)
                                }
                                
                                Text(repo.name).font(.headline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    // VUỐT ĐỂ XOÁ
                    .onDelete { offsets in
                        storeManager.removeRepo(at: offsets)
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

// MARK: - RepoDetailView (Giao diện chuẩn ảnh 3 & 4)
struct RepoDetailView: View {
    let repo: ThemeRepo
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Phần Header (Icon, Tên, Mô tả lỗi)
                if let error = repo.errorMessage {
                    VStack(spacing: 12) {
                        // Box hiển thị tên Repo và Lỗi (Giống ảnh 3 & 4)
                        HStack(alignment: .top, spacing: 12) {
                            if let iconURL = repo.iconURL {
                                AsyncImage(url: iconURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 50, height: 50)
                                .cornerRadius(8)
                            } else {
                                Text(String(repo.name.prefix(1)).uppercased())
                                    .font(.title3.bold())
                                    .foregroundColor(.red)
                                    .frame(width: 50, height: 50)
                                    .background(Color.red.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(repo.name).font(.headline)
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(.red)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        
                        // Box thông báo trống (Giống ảnh 4)
                        Text("Nguồn này chưa có gói khả dụng. Hãy bật hoặc làm mới nguồn rồi thử lại.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                } else if repo.themes.isEmpty {
                    ContentUnavailableView("Không có gói nào", systemImage: "tray", description: Text("Nguồn này chưa có gói khả dụng. Hãy bật hoặc làm mới nguồn rồi thử lại."))
                        .padding(.top, 40)
                } else {
                    // Hiển thị danh sách theme nếu thành công
                    LazyVStack(spacing: 0) {
                        ForEach(Array(repo.themes.enumerated()), id: \.element.id) { index, theme in
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
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding()
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                            }
                            .buttonStyle(.plain)
                            
                            if index < repo.themes.count - 1 {
                                Divider().padding(.leading, 80)
                            }
                        }
                    }
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - RemoteThemeDownloadView (Giữ nguyên)
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