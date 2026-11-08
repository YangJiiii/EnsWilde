import SwiftUI

struct ConfigView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var toolStore: ToolStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @AppStorage("ConfigFootnoteText") private var footnoteText: String = ""
    @AppStorage("ConfigSupervised") private var supervised: Bool = false
    @AppStorage("ConfigOrgName") private var orgName: String = ""
    
    @State private var showSavedAlert = false

    var body: some View {
        Form {
            Section(header: Text(L("config_tweaks_title"))) {
                Toggle(L("enable_tweak"), isOn: $toolStore.configTweaksEnabled)
            }

            Section(header: Text(L("lock_screen_footnote"))) {
                TextField(L("custom_footnote_placeholder"), text: $footnoteText)
                    .autocorrectionDisabled()
                
                if !footnoteText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("preview_label")).font(.caption).foregroundStyle(.secondary)
                        Text(footnoteText)
                            .font(.body)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }

            Section(header: Text(L("supervision_title"))) {
                Toggle(L("enable_supervision"), isOn: $supervised)
                
                if supervised {
                    TextField(L("org_name_placeholder"), text: $orgName)
                        .autocorrectionDisabled()
                    
                    if !orgName.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("preview_label")).font(.caption).foregroundStyle(.secondary)
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
                        Text(L("apply_save_changes")).font(.headline)
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
                        Text(L("restore_save_changes")).font(.headline)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(L("config_tweaks_title"))
        .alert(L("saved_title"), isPresented: $showSavedAlert) {
            Button(L("alert_ok")) {}
        } message: {
            Text(L("saved_message"))
        }
    }
}