import SwiftUI

// MARK: - Root Theme Store View

struct ThemeStoreView: View {
    @StateObject private var storeManager = ThemeStoreManager()
    @ObservedObject var themeStore: PasscodeThemeStore
    @State private var showAddSheet = false
    
    private var localizationManager: LocalizationManager { LocalizationManager.shared }
    
    var body: some View {
        Group {
            if let indexed = storeManager.selectedIndexedRepo {
                ThemesListView(
                    title: indexed.name,
                    themeStore: themeStore,
                    storeManager: storeManager,
                    backAction: { storeManager.backToIndexedRepos() },
                    backLabel: storeManager.selectedRepository?.name ?? "Back"
                )
            } else if let repo = storeManager.selectedRepository {
                if repo.isIndex {
                    IndexedRepositoriesListView(storeManager: storeManager, themeStore: themeStore)
                } else {
                    ThemesListView(
                        title: repo.name,
                        themeStore: themeStore,
                        storeManager: storeManager,
                        backAction: { storeManager.backToRepositories() },
                        backLabel: L("theme_store_title")
                    )
                }
            } else {
                RepositoriesListView(storeManager: storeManager)
            }
        }
        .navigationTitle(L("theme_store_title"))
        .toolbar {
            if storeManager.selectedRepository == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRepoSheet(storeManager: storeManager)
        }
    }
}

// MARK: - Repositories List View (top-level)

struct RepositoriesListView: View {
    @ObservedObject var storeManager: ThemeStoreManager
    
    var body: some View {
        Form {
            if storeManager.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(L("theme_store_loading"))
                        Spacer()
                    }.padding(.vertical, 20)
                }
            } else if let error = storeManager.errorMessage {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text(error).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await refreshAll() } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else if storeManager.repositories.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Chưa có repo — bấm + để thêm")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section(header: Text(L("theme_store_title"))) {
                    ForEach(storeManager.repositories) { repo in
                        RepositoryRowView(repository: repo, storeManager: storeManager)
                            .contextMenu {
                                Button(role: .destructive) {
                                    storeManager.removeRepo(repo)
                                } label: {
                                    Label("Xoá repo", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .headerProminence(.increased)
        .refreshable {
            await refreshAll()
        }
    }
    
    private func refreshAll() async {
        // Reset về trạng thái idle, để row tự fetch lại count
    }
}

// MARK: - Repository Row

struct RepositoryRowView: View {
    let repository: ThemeRepository
    @ObservedObject var storeManager: ThemeStoreManager
    @State private var themeCount: Int?
    
    var body: some View {
        Button {
            Task {
                if repository.isIndex {
                    await storeManager.fetchIndexedRepos(from: repository)
                } else {
                    await storeManager.fetchThemes(from: repository)
                }
            }
        } label: {
            HStack(spacing: 12) {
                repoIcon
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.body)
                        .foregroundStyle(.primary)  // ← chữ trắng, không cam
                    
                    if let count = themeCount {
                        Text("\(count) themes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if repository.isIndex {
                        Text("Index · Tap to open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .task {
            await fetchCount()
        }
    }
    
    @ViewBuilder
    private var repoIcon: some View {
        if let iconStr = repository.iconURL, let url = URL(string: iconStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }
    
    private var fallbackIcon: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 22))
            .foregroundStyle(.secondary)   // ← xám, không cam
            .frame(width: 40, height: 40)
    }
    
    private func fetchCount() async {
        guard let url = repository.jsonURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let _ = try? JSONDecoder().decode([IndexedRepository].self, from: data) {
                themeCount = nil
            } else if let repoJSON = try? JSONDecoder().decode(RepoJSONCodable.self, from: data) {
                themeCount = (repoJSON.themes ?? repoJSON.packages ?? []).count
            } else if let themes = try? JSONDecoder().decode([RemoteThemeCodable].self, from: data) {
                themeCount = themes.count
            }
        } catch { }
    }
}

// MARK: - Indexed Repositories List View (sub-repos trong index)

struct IndexedRepositoriesListView: View {
    @ObservedObject var storeManager: ThemeStoreManager
    @ObservedObject var themeStore: PasscodeThemeStore
    
    var body: some View {
        Form {
            if storeManager.isLoading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20)
                }
            } else if let error = storeManager.errorMessage {
                Section {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") {
                            if let r = storeManager.selectedRepository {
                                Task { await storeManager.fetchIndexedRepos(from: r) }
                            }
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            } else if storeManager.indexedRepositories.isEmpty {
                Section {
                    Text("Index không có sub-repo")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            } else {
                Section {
                    ForEach(storeManager.indexedRepositories) { indexed in
                        Button {
                            Task { await storeManager.fetchThemes(from: indexed) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(indexed.name).foregroundStyle(.primary)
                                    Text("Tap to open")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(storeManager.selectedRepository?.name ?? "Repos")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    storeManager.backToRepositories()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(L("theme_store_title"))
                    }
                }
            }
        }
    }
}

// MARK: - Themes Grid View

struct ThemesListView: View {
    let title: String
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    let backAction: () -> Void
    let backLabel: String
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            if storeManager.isLoading {
                ProgressView(L("theme_store_loading"))
                    .frame(maxWidth: .infinity).padding(.top, 60)
            } else if let error = storeManager.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48)).foregroundStyle(.red)
                    Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") {
                        Task {
                            if let idx = storeManager.selectedIndexedRepo {
                                await storeManager.fetchThemes(from: idx)
                            } else if let r = storeManager.selectedRepository {
                                await storeManager.fetchThemes(from: r)
                            }
                        }
                    }
                }.padding(.top, 60)
            } else if storeManager.remoteThemes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(L("theme_store_no_themes")).foregroundStyle(.secondary)
                }.padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(storeManager.remoteThemes) { theme in
                        RemoteThemeCardView(theme: theme, themeStore: themeStore, storeManager: storeManager)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: backAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(backLabel)
                    }
                }
            }
        }
        .refreshable {
            if let idx = storeManager.selectedIndexedRepo {
                await storeManager.fetchThemes(from: idx)
            } else if let r = storeManager.selectedRepository {
                await storeManager.fetchThemes(from: r)
            }
        }
    }
}

// MARK: - Theme Card

struct RemoteThemeCardView: View {
    let theme: RemoteTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    @State private var previewImage: UIImage?
    @State private var isDownloading = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    private var isDownloaded: Bool {
        themeStore.themes.contains { $0.name == theme.name }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if let img = previewImage {
                Image(uiImage: img)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(height: 120).clipped()
                    .cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 120)
                    .overlay(ProgressView())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                Text("by \(theme.authors)").font(.caption2)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if isDownloaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.caption2)
                    Text(L("theme_store_downloaded")).font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity).frame(height: 32)
            } else {
                Button {
                    downloadTheme()
                } label: {
                    HStack(spacing: 4) {
                        if isDownloading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.down.circle.fill").font(.caption2)
                        }
                        Text(isDownloading ? L("theme_store_downloading") : L("theme_store_download_import"))
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(AppTheme.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
                .opacity(isDownloading ? 0.55 : 1.0)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .task { await loadPreview() }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: { Text(errorMessage) }
    }
    
    private func loadPreview() async {
        guard let url = theme.previewURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                await MainActor.run { previewImage = img }
            }
        } catch { }
    }
    
    private func downloadTheme() {
        isDownloading = true
        Task {
            do {
                try await storeManager.downloadAndImportTheme(theme, themeStore: themeStore)
                await MainActor.run { isDownloading = false }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Add Repo Sheet

struct AddRepoSheet: View {
    @ObservedObject var storeManager: ThemeStoreManager
    @Environment(\.dismiss) var dismiss
    @State private var urlText = ""
    @State private var isAdding = false
    @State private var errorText: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://raw.githubusercontent.com/.../themes.json", text: $urlText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Repo URL")
                } footer: {
                    Text("Hỗ trợ cả file index (nhiều sub-repo) và file themes trực tiếp. Tự nhận dạng tên + icon từ JSON.")
                }
                
                if let err = errorText {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text(err).foregroundStyle(.red).font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Add Repo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task { await add() }
                        }
                        .bold()
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
    
    private func add() async {
        isAdding = true
        errorText = nil
        defer { isAdding = false }
        do {
            try await storeManager.addRepo(urlString: urlText)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}