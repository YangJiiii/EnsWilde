//  DisableCallRecordingSoundView.swift
//  EnsWilde

import SwiftUI

struct DisableCallRecordingSoundView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @Environment(\.dismiss) var dismiss
    
    @State private var showSavedAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Tweak", isOn: $toolStore.disableCallRecordingSoundEnabled)
            } // Đã xoá caption

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
        }
        .navigationTitle("Disable Call Recording Sound")
        .navigationBarTitleDisplayMode(.inline)
        // Popup thông báo
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {
                showApplyTab = true
                dismiss()
            }
        } message: {
            Text("Changes saved. Please go to the Apply tab to apply them.")
        }
    }
}