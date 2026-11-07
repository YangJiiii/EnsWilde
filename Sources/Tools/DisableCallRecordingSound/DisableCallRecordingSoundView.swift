import SwiftUI

struct DisableCallRecordingSoundView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @Environment(\.dismiss) var dismiss
    
    @State private var showSavedAlert = false
    @State private var isRestoring = false
    @State private var restoreError: String?
    
    @StateObject private var vm = DisableCallRecordingSoundViewModel()

    var body: some View {
        Form {
            // PHẦN 1: TONE STATUS
            Section {
                HStack {
                    Text("Current Tone")
                    Spacer()
                    Text(vm.toneStatus)
                        .foregroundStyle(vm.isToneSilenced ? .orange : .green)
                        .fontWeight(.semibold)
                }
                Button {
                    Task {
                        await vm.checkToneStatus()
                    }
                } label: {
                    HStack {
                        Image(systemName: "waveform")
                        Text(vm.isChecking ? "Checking..." : "Check Tone Status")
                    }
                }
                .disabled(vm.isChecking)
            } header: {
                Text("Tone Status")
            } footer: {
                Text("Kiểm tra xem file âm thanh trên máy đang là file gốc của Apple hay đã bị ghi đè bằng file im lặng.")
            }

            // PHẦN 2: BACKUP STATUS
            Section {
                HStack {
                    Text("Backup Status")
                    Spacer()
                    Text(vm.backupStatus)
                        .foregroundStyle(vm.isBackupReady ? .green : .secondary)
                        .fontWeight(.semibold)
                }
                Button("Refresh Backup Status") {
                    vm.checkBackupStatus()
                }
            } header: {
                Text("Backup System")
            } footer: {
                Text("Ở lần Apply đầu tiên, App sẽ tự động trích xuất file gốc vào bộ nhớ máy.")
            }

            Section {
                Toggle("Enable Tweak", isOn: $toolStore.disableCallRecordingSoundEnabled)
            }

            Section {
                Button {
                    showSavedAlert = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Changes").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .disabled(!toolStore.disableCallRecordingSoundEnabled)
            }
            
            // PHẦN 3: NÚT RESTORE
            Section {
                Button(role: .destructive) {
                    restoreSounds()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(isRestoring ? "Restoring..." : "Restore Default Sounds").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .disabled(isRestoring || !vm.isBackupReady)
            } footer: {
                Text("Khôi phục lại âm thanh gốc từ bản Backup đã được tạo tự động.")
            }
        }
        .navigationTitle("Disable Call Recording Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.checkBackupStatus()
            Task {
                await vm.checkToneStatus()
            }
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {
                showApplyTab = true
                dismiss()
            }
        } message: {
            Text("Changes saved. Please go to the Apply tab to apply them.")
        }
        .alert("Lỗi Restore", isPresented: .init(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }
    
    private func restoreSounds() {
        isRestoring = true
        Task {
            do {
                try await vm.apply(store: toolStore, isRestore: true) { log in
                    print(log)
                }
                await MainActor.run {
                    toolStore.disableCallRecordingSoundEnabled = false
                    isRestoring = false
                    showSavedAlert = true 
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    restoreError = error.localizedDescription
                }
            }
        }
    }
}