import SwiftUI

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ConfigFootnoteText") private var footnoteText: String = ""
    @AppStorage("ConfigSupervised") private var supervised: Bool = false
    @AppStorage("ConfigOrgName") private var orgName: String = ""

    @State private var showSavedAlert = false

    var body: some View {
        Form {
            Section(header: Text("Config Tweaks")) {
                // Bỏ icon, chỉ để Toggle
                Toggle("Enable Tweak", isOn: $toolStore.configTweaksEnabled)
            }

            Section(header: Text("Lock Screen Footnote")) {
                // Bỏ icon, chỉ để TextField với placeholder
                TextField("Nhập chữ cho màn hình khoá...", text: $footnoteText)
                    .autocorrectionDisabled()
                
                // Khung preview
                if !footnoteText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    // Ô nhập Organization Name với placeholder xám
                    TextField("Nhập tên tổ chức (Organization Name)...", text: $orgName)
                        .autocorrectionDisabled()
                    
                    // Khung preview
                    if !orgName.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    }
                    .frame(maxWidth: .infinity)
                }

                Button(role: .destructive) {
                    // Xoá sạch dữ liệu
                    toolStore.configTweaksEnabled = false
                    footnoteText = ""
                    supervised = false
                    orgName = ""
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restore Save Changes").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Config Tweaks")
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Đã lưu. Chuyển sang tab Apply để áp dụng.")
        }
    }
}