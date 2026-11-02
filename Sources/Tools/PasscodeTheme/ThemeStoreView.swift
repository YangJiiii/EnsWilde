import SwiftUI

struct ThemeStoreView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @StateObject private var storeManager = ThemeStoreManager()
    @State private var selectedRemoteTheme: RemoteTheme?
    @StateObject private var viewModel: PasscodeThemeViewModel
    @State private var selectedType: RemoteTheme.ThemeType = .passcode
    
    init(themeStore: PasscodeThemeStore) {
        self.themeStore = themeStore
        _viewModel = StateObject(wrappedValue: PasscodeThemeViewModel(store: themeStore))
    }

    var body: some View {
        VStack {
            // Picker chọn loại theme
            Picker("Loại Theme", selection: $selectedType) {
                Text("Passcode").tag(RemoteTheme.ThemeType.passcode)
                Text("Wallet").tag(RemoteTheme.ThemeType.wallet)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            
            Group {
                if storeManager.isLoading {
                    ProgressView("Loading themes...")
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
                } else {
                    let filteredThemes = storeManager.themes.filter { $0.type == selectedType || $0.type == .unknown }
                    if filteredThemes.isEmpty {
                        ContentUnavailableView("No Themes", systemImage: "paintpalette", description: Text("Không có theme nào cho loại này."))
                    } else {
                        List(filteredThemes) { theme in
                            Button {
                                selectedRemoteTheme = theme
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: URL(string: theme.preview)) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(theme.name).font(.headline)
                                        Text(theme.authors).font(.caption).foregroundStyle(.secondary)
                                        Text(theme.type == .passcode ? "Passcode" : theme.type == .wallet ? "Wallet" : "Unknown")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Theme Store")
        .task {
            if storeManager.themes.isEmpty {
                await storeManager.fetchThemes()
            }
        }
        .sheet(item: $selectedRemoteTheme) { remoteTheme in
            RemoteThemeDownloadView(remoteTheme: remoteTheme, themeStore: themeStore, viewModel: viewModel)
        }
    }
}

// MARK: - Remote Theme Download View (Xử lý import đúng loại)
struct RemoteThemeDownloadView: View {
    let remoteTheme: RemoteTheme
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var viewModel: PasscodeThemeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isDownloading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AsyncImage(url: URL(string: remoteTheme.preview)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 200)
                .cornerRadius(12)
                
                Text(remoteTheme.name).font(.title2.bold())
                Text(remoteTheme.description ?? "").foregroundStyle(.secondary)
                Text("Loại: \(remoteTheme.type == .passcode ? "Passcode" : remoteTheme.type == .wallet ? "Wallet" : "Không rõ")")
                    .font(.caption)
                    .foregroundStyle(.blue)
                
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func downloadAndImport() async {
        isDownloading = true
        errorMessage = nil
        
        do {
            guard let url = URL(string: remoteTheme.url) else {
                throw PasscodeThemeError.invalidFormat
            }
            
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            
            // Xử lý theo loại theme
            switch remoteTheme.type {
            case .passcode:
                // Import theme passcode (.passthm)
                try await viewModel.importTheme(from: tempURL, name: remoteTheme.name)
            case .wallet:
                // Import theme wallet (có thể là .zip chứa ảnh card)
                // Tạm thời dùng logic import wallet nếu có, hoặc báo lỗi
                errorMessage = "Wallet theme import chưa được hỗ trợ trong view này. Vui lòng dùng AirCard."
                isDownloading = false
                return
            case .unknown:
                // Thử import như passcode
                try await viewModel.importTheme(from: tempURL, name: remoteTheme.name)
            }
            
            dismiss()
            
        } catch {
            errorMessage = "Failed to import: \(error.localizedDescription)"
        }
        
        isDownloading = false
    }
}