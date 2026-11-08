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
                    Text(L("current_tone"))
                    Spacer()
                    Text(L(vm.toneStatusKey))
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
                        Text(vm.isChecking ? L("checking") : L("check_tone_status"))
                    }
                }
                .disabled(vm.isChecking)
            } header: {
                Text(L("tone_status"))
            } footer: {
                Text(L("tone_status_footer"))
            }

            // PHẦN 2: BACKUP STATUS
            Section {
                HStack {
                    Text(L("backup_status"))
                    Spacer()
                    Text(L(vm.backupStatusKey))
                        .foregroundStyle(vm.isBackupReady ? .green : .secondary)
                        .fontWeight(.semibold)
                }
                Button(L("refresh_backup_status")) {
                    vm.checkBackupStatus()
                }
            } header: {
                Text(L("backup_system"))
            } footer: {
                Text(L("backup_system_footer"))
            }

            Section {
                Toggle(L("enable_tweak"), isOn: $toolStore.disableCallRecordingSoundEnabled)
            }

            Section {
                Button {
                    showSavedAlert = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(L("save_changes")).font(.headline)
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
                        Text(isRestoring ? L("restoring") : L("restore_default_sounds")).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .disabled(isRestoring || !vm.isBackupReady)
            } footer: {
                Text(L("restore_footer"))
            }
        }
        .navigationTitle(L("recording_sound_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.checkBackupStatus()
            Task {
                await vm.checkToneStatus()
            }
        }
        .alert(L("saved_title"), isPresented: $showSavedAlert) {
            Button(L("alert_ok")) {
                showApplyTab = true
                dismiss()
            }
        } message: {
            Text(L("saved_message"))
        }
        .alert(L("restore_error_title"), isPresented: .init(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button(L("alert_ok"), role: .cancel) { restoreError = nil }
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