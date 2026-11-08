import SwiftUI

// MARK: - Root Theme Store View

struct ThemeStoreView: View {
    @StateObject private var storeManager = ThemeStoreManager()
    @ObservedObject var themeStore: PasscodeThemeStore
    @State private var showAddSheet = false
    
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
                        backLabel: "Theme Store"
                    )
                }
            } else {
                RepositoriesListView(storeManager: storeManager)
            }
        }
        .navigationTitle("Theme Store")
        .toolbar {
            if storeManager.selectedRepository == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRepoSheet(storeManager: storeManager)
        }
    }
}

// MARK: - Repositories List

struct RepositoriesListView: View {
    @ObservedObject var storeManager: ThemeStoreManager
    
    var body: some View {
        Form {
            if storeManager.isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20) }
            } else if storeManager.repositories.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "folder").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No repos added. Tap + to add.").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            } else {
                Section(header: Text("Repositories")) {
                    ForEach(storeManager.repositories) { repo in
                        RepositoryRowView(repository: repo, storeManager: storeManager)
                            .contextMenu {
                                Button(role: .destructive) { storeManager.removeRepo(repo) } label: {
                                    Label("Delete Repo", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .headerProminence(.increased)
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
                if repository.isIndex { await storeManager.fetchIndexedRepos(from: repository) }
                else { await storeManager.fetchThemes(from: repository) }
            }
        } label: {
            HStack(spacing: 12) {
                repoIcon.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name).font(.body).foregroundStyle(.primary)
                    if let count = themeCount {
                        Text("\(count) themes").font(.caption).foregroundStyle(.secondary)
                    } else if repository.isIndex {
                        Text("Index · Tap to open").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Loading...").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .task { await fetchCount() }
    }
    
    @ViewBuilder private var repoIcon: some View {
        if let iconStr = repository.iconURL, let url = URL(string: iconStr) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "folder.fill").font(.system(size: 22)).foregroundStyle(.secondary).frame(width: 40, height: 40)
                }
            }
        } else {
            Image(systemName: "folder.fill").font(.system(size: 22)).foregroundStyle(.secondary).frame(width: 40, height: 40)
        }
    }
    
    private func fetchCount() async {
        guard let url = repository.jsonURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) {
                if let arr = json as? [[String: Any]], arr.contains(where: { $0["baseURL"] != nil }) {
                    themeCount = nil // Is index
                } else if let dict = json as? [String: Any] {
                    themeCount = (dict["themes"] as? [[String: Any]] ?? dict["packages"] as? [[String: Any]])?.count
                } else if let arr = json as? [[String: Any]] {
                    themeCount = arr.count
                }
            }
        } catch { }
    }
}

// MARK: - Indexed Sub-repos List

struct IndexedRepositoriesListView: View {
    @ObservedObject var storeManager: ThemeStoreManager
    @ObservedObject var themeStore: PasscodeThemeStore
    
    var body: some View {
        Form {
            if storeManager.isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20) }
            } else if storeManager.indexedRepositories.isEmpty {
                Section { Text("No sub-repos found.").foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(storeManager.indexedRepositories) { indexed in
                        Button {
                            Task { await storeManager.fetchThemes(from: indexed) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill").font(.system(size: 22)).foregroundStyle(.secondary).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(indexed.name).foregroundStyle(.primary)
                                    Text("Tap to open").font(.caption).foregroundStyle(.secondary)
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
                Button { storeManager.backToRepositories() } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Theme Store") }
                }
            }
        }
    }
}

// MARK: - Themes Grid List

struct ThemesListView: View {
    let title: String
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var storeManager: ThemeStoreManager
    let backAction: () -> Void
    let backLabel: String
    
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    
    var body: some View {
        ScrollView {
            if storeManager.isLoading {
                ProgressView("Loading...").frame(maxWidth: .infinity).padding(.top, 60)
            } else if storeManager.remoteThemes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("No themes found.").foregroundStyle(.secondary)
                }.padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(storeManager.remoteThemes) { theme in
                        RemoteThemeCardView(theme: theme, themeStore: themeStore, storeManager: storeManager)
                    }
                }.padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: backAction) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text(backLabel) }
                }
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
    
    private var isDownloaded: Bool { themeStore.themes.contains { $0.name == theme.name } }
    
    var body: some View {
        VStack(spacing: 8) {
            if let img = previewImage {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).frame(height: 120).clipped().cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15)).frame(height: 120).overlay(ProgressView())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("by \(theme.authors)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            
            if isDownloaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.caption2)
                    Text("Downloaded").font(.caption2.weight(.semibold))
                }.foregroundStyle(.green).frame(maxWidth: .infinity).frame(height: 32)
            } else {
                Button { downloadTheme() } label: {
                    HStack(spacing: 4) {
                        if isDownloading { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "arrow.down.circle.fill").font(.caption2) }
                        Text(isDownloading ? "Downloading..." : "Download").font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(AppTheme.accent).foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(isDownloading)
            }
        }
        .padding(10).background(Color(.secondarySystemGroupedBackground)).cornerRadius(14)
        .task { await loadPreview() }
        .alert("Error", isPresented: $showErrorAlert) { Button("OK") {} } message: { Text(errorMessage) }
    }
    
    private func loadPreview() async {
        guard let url = theme.previewURL else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) {
            await MainActor.run { previewImage = img }
        }
    }
    
    private func downloadTheme() {
        isDownloading = true
        Task {
            do {
                try await storeManager.downloadAndImportTheme(theme, themeStore: themeStore)
                await MainActor.run { isDownloading = false }
            } catch {
                await MainActor.run { isDownloading = false; errorMessage = error.localizedDescription; showErrorAlert = true }
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
                    TextField("https://...", text: $urlText)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                } header: { Text("Repo JSON URL") } footer: {
                    Text("Supports index files or direct theme JSONs. Auto-detects name & icon.")
                }
                
                if let err = errorText {
                    Section {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Repo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding { ProgressView() }
                    else {
                        Button("Add") { Task { await add() } }
                            .bold().disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
    
    private func add() async {
        isAdding = true; errorText = nil; defer { isAdding = false }
        do { try await storeManager.addRepo(urlString: urlText); dismiss() }
        catch { errorText = error.localizedDescription }
    }
}