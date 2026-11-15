import SwiftUI

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ConfigFootnoteText") private var footnoteText: String = ""
    @AppStorage("ConfigSupervised") private var supervised: Bool = false
    @AppStorage("ConfigOrgName") private var orgName: String = ""
    
    @State private var showSavedAlert = false
    @State private var showRestoredAlert = false

    var body: some View {
        Form {
            Section(header: Text("Config Tweaks")) {
                Toggle("Enable Tweak", isOn: $toolStore.configTweaksEnabled)
            }

            Section(header: Text("Lock Screen Footnote")) {
                TextField("Nhập chữ cho màn hình khoá...", text: $footnoteText)
                    .autocorrectionDisabled()
                
                if !footnoteText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview:").font(.caption).foregroundStyle(.secondary)
                        Text(footnoteText)
                            .font(.body)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }

            Section(header: Text("Supervision")) {
                Toggle("Enable Supervision", isOn: $supervised)
                
                if supervised {
                    TextField("Nhập tên tổ chức (Organization Name)...", text: $orgName)
                        .autocorrectionDisabled()
                    
                    if !orgName.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview:").font(.caption).foregroundStyle(.secondary)
                            Text(orgName)
                                .font(.body)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                }
            }

            Section {
                Button {
                    showApplyTab = true
                    showSavedAlert = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Apply Save Changes").font(.headline)
                    }.frame(maxWidth: .infinity)
                }

                Button(role: .destructive) {
                    // 🔥 FIX: KHÔNG tắt toolStore.configTweaksEnabled
                    // Chỉ clear các field. Toggle giữ ON để Apply vẫn chạy → xoá file trên máy.
                    footnoteText = ""
                    supervised = false
                    orgName = ""
                    
                    showRestoredAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restore Save Changes").font(.headline)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Config Tweaks")
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Đã lưu. Chuyển sang tab Apply để áp dụng.")
        }
        .alert("Restored", isPresented: $showRestoredAlert) {
            Button("OK") {}
        } message: {
            Text("Đã xoá toàn bộ cấu hình. Hãy sang tab Apply để hoàn tất việc xoá trên thiết bị.")
        }
    }
}