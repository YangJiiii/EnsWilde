//  DisableCallRecordingSoundView.swift
//  EnsWilde

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
            
            // NÚT RESTORE
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
                .disabled(isRestoring)
            } footer: {
                Text("Khôi phục lại âm thanh gốc từ bộ nhớ Backup của App. (App sẽ tự động sao lưu file gốc ở lần Apply đầu tiên).")
            }
        }
        .navigationTitle("Disable Call Recording Sound")
        .navigationBarTitleDisplayMode(.inline)
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
                    toolStore.disableCallRecordingSoundEnabled = false // Tắt toggle
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