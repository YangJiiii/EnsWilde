import SwiftUI

struct ThemesUIView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var toolStore: ToolStore
    let globalPrefsURL: URL
    let springboardPrefsURL: URL
    
    @State private var solariumForceFallback = false
    @State private var disableSolarium = false
    @State private var ignoreSolariumLinkedOnCheck = false
    @State private var disallowGlassTime = false
    @State private var disableGlassDock = false
    @State private var disableSpecularMotion = false
    @State private var disableOuterRefraction = false
    @State private var allowHDR = true
    
    @State private var suppressDynamicIsland = false
    
    var body: some View {
        Form {
            Section(L("themes_ui_title")) {
                Toggle(L("enable_tool"), isOn: $toolStore.themesUIEnabled)
            }

            Section(header: Text(L("section_liquid_glass"))) {
                Toggle(L("themes_force_fallback"), isOn: $solariumForceFallback)
                    .onChange(of: solariumForceFallback) { autoSave() }

                Toggle(L("themes_disable_swiftui"), isOn: $disableSolarium)
                    .onChange(of: disableSolarium) { autoSave() }

                Toggle(L("themes_ignore_check"), isOn: $ignoreSolariumLinkedOnCheck)
                    .onChange(of: ignoreSolariumLinkedOnCheck) { autoSave() }

                Toggle(L("themes_disable_glass_time"), isOn: $disallowGlassTime)
                    .onChange(of: disallowGlassTime) { autoSave() }

                Toggle(L("themes_disable_glass_dock"), isOn: $disableGlassDock)
                    .onChange(of: disableGlassDock) { autoSave() }

                Toggle(L("themes_disable_specular"), isOn: $disableSpecularMotion)
                    .onChange(of: disableSpecularMotion) { autoSave() }

                Toggle(L("themes_disable_refraction"), isOn: $disableOuterRefraction)
                    .onChange(of: disableOuterRefraction) { autoSave() }

                Toggle(L("themes_disable_hdr"), isOn: Binding(
                    get: { !allowHDR },
                    set: { allowHDR = !$0 }
                ))
                .onChange(of: allowHDR) { autoSave() }
            }

            Section(header: Text(L("themes_springboard_section"))) {
                Toggle(L("themes_hide_dynamic_island"), isOn: $suppressDynamicIsland)
                    .onChange(of: suppressDynamicIsland) { autoSave() }
            }

            Section(header: Text(L("section_save_settings"))) {
                Button(L("themes_reset_button"), role: .destructive) {
                    resetAllSettings()
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("themes_ui_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAllPreferences()
        }
    }

    private func loadAllPreferences() {
        if FileManager.default.fileExists(atPath: globalPrefsURL.path) {
            if let dict = NSDictionary(contentsOf: globalPrefsURL) as? [String: Any] {
                solariumForceFallback = (dict["SolariumForceFallback"] as? Bool) ?? false
                disableSolarium = (dict["com.apple.SwiftUI.DisableSolarium"] as? Bool) ?? false
                ignoreSolariumLinkedOnCheck = (dict["com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"] as? Bool) ?? false
                disallowGlassTime = (dict["SBDisallowGlassTime"] as? Bool) ?? false
                disableGlassDock = (dict["SBDisableGlassDock"] as? Bool) ?? false
                disableSpecularMotion = (dict["SBDisableSpecularEverywhereUsingLSSAssertion"] as? Bool) ?? false
                disableOuterRefraction = (dict["SolariumDisableOuterRefraction"] as? Bool) ?? false
                allowHDR = (dict["SolariumAllowHDR"] as? Bool) ?? true
            }
        }

        if FileManager.default.fileExists(atPath: springboardPrefsURL.path) {
            if let dict = NSDictionary(contentsOf: springboardPrefsURL) as? [String: Any] {
                suppressDynamicIsland = (dict["SBSuppressDynamicIslandCompletely"] as? Bool) ?? false
            }
        }
        
        autoSave()
    }

    private func autoSave() {
        let globalDict = NSMutableDictionary()
        if solariumForceFallback { globalDict["SolariumForceFallback"] = true }
        if disableSolarium { globalDict["com.apple.SwiftUI.DisableSolarium"] = true }
        if ignoreSolariumLinkedOnCheck { globalDict["com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck"] = true }
        if disallowGlassTime { globalDict["SBDisallowGlassTime"] = true }
        if disableGlassDock { globalDict["SBDisableGlassDock"] = true }
        if disableSpecularMotion { globalDict["SBDisableSpecularEverywhereUsingLSSAssertion"] = true }
        if disableOuterRefraction { globalDict["SolariumDisableOuterRefraction"] = true }
        if !allowHDR { globalDict["SolariumAllowHDR"] = false }
        try? (globalDict as NSDictionary).write(to: globalPrefsURL)

        let sbDict: NSDictionary = ["SBSuppressDynamicIslandCompletely": suppressDynamicIsland]
        try? sbDict.write(to: springboardPrefsURL)

        toolStore.themesUIEnabled = true
    }

    private func resetAllSettings() {
        solariumForceFallback = false
        disableSolarium = false
        ignoreSolariumLinkedOnCheck = false
        disallowGlassTime = false
        disableGlassDock = false
        disableSpecularMotion = false
        disableOuterRefraction = false
        allowHDR = true
        suppressDynamicIsland = false
        autoSave()
    }
    
    init(toolStore: ToolStore) {
        self.toolStore = toolStore
        let documentsDirectory = URL.documentsDirectory
        globalPrefsURL = documentsDirectory.appendingPathComponent("GlobalPreferences.plist")
        springboardPrefsURL = documentsDirectory.appendingPathComponent("SpringboardPreferences.plist")
    }
}