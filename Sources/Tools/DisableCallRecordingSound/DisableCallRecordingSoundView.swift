//  DisableCallRecordingSoundView.swift
//  EnsWilde

import SwiftUI

struct DisableCallRecordingSoundView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Tweak", isOn: $toolStore.disableCallRecordingSoundEnabled)
            } footer: {
                Text("Thay thế âm thanh thông báo bắt đầu và kết thúc ghi âm cuộc gọi bằng âm thanh im lặng. File gốc sẽ bị ghi đè.")
            }

            Section {
                Button {
                    showApplyTab = true
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
    }
}
