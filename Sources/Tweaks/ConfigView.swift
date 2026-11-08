import SwiftUI

struct ConfigView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ConfigFootnoteText") private var footnoteText: String = ""
    @AppStorage("ConfigSupervised") private var supervised: Bool = false
    @AppStorage("ConfigOrgName") private var orgName: String = ""
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false   // ← NEW

    @State private var showSavedAlert = false

    var body: some View {
        Group {
            if isAirLiftMode {
                airliftUnavailable
            } else {
                formContent
            }
        }
        .navigationTitle("Config Tweaks")
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Đã lưu. Chuyển sang tab Apply để áp dụng.")
        }
    }

    @ViewBuilder
    private var airliftUnavailable: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Not Available in Airlift Mode")
                .font(.headline)
            Text("Config Tweaks requires native iOS access. You chose Airlift-only mode.\n\nOnly Passcode Theme is available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var formContent: some View {
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
                    toolStore.configTweaksEnabled = false
                    footnoteText = ""
                    supervised = false
                    orgName = ""

                    UserDefaults.standard.removeObject(forKey: "ConfigFootnoteText")
                    UserDefaults.standard.removeObject(forKey: "ConfigSupervised")
                    UserDefaults.standard.removeObject(forKey: "ConfigOrgName")
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restore Save Changes").font(.headline)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}