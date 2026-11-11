import SwiftUI
import UniformTypeIdentifiers
import AirliftFFI

// Custom Icon siêu mỏng, không màu mè
struct CleanTweakIcon: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .light)) // Nét mỏng
            .frame(width: 28, height: 28)
            .background(Color.secondary.opacity(0.1)) // Nền xám mờ tinh tế
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) // Bo góc nhẹ
    }
}

// ĐÃ RENAME: tránh trùng với IconPickerLabel trong TweakRowIcon.swift
struct MGIconPickerLabel: View {
    let title: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 12) {
            CleanTweakIcon(systemImage: systemImage)
            Text(title)
        }
    }
}

struct MobileGestaltView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    let origMGURL, modMGURL, featFlagsURL, resolutionURL: URL
    @Environment(\.scenePhase) var scenePhase
    @ObservedObject var toolStore: ToolStore
    @StateObject private var store = GestaltStore.shared

    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false

    @State var mbdb: Backup?
    @State var eligibilityData = Data()
    @State var featureFlagsData = Data()
    @State var mobileGestalt: NSMutableDictionary
    @State var productType = machineName()
    @State var respring = true
    @State var showPairingFileImporter = false
    @State var showErrorAlert = false
    @State var taskRunning = false
    @State var initError: String?
    @State var lastError: String?
    @State var dynamicIslandType: Int = 0

    // Custom Subtype State
    @State var enableCustomSubtype: Bool = false
    @State var customSubtypeValue: String = ""

    @State var enableModelName: Bool = false
    @State var modelName: String = ""

    var body: some View {
        Form {
            enableSection
            deviceSubtypeSection
            hardwareFeaturesSection
            displayAndUISection
            systemFeaturesSection
            advancedSection
            saveResetSection
        }
        .headerProminence(.increased)
        .alert("Message", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(lastError ?? "???")
        }
        .navigationTitle(L("tool_mobile_gestalt"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Đảm bảo Store có dữ liệu
            if store.mgCurrentDict.count == 0 {
                store.loadFromPlist(url: modMGURL)
            }
            
            if initError != nil {
                lastError = initError
                initError = nil
                showErrorAlert.toggle()
                return
            }
            // Đồng bộ lại UI từ Store
            mobileGestalt = store.mgCurrentDict
            hydrateFromDict()
        }
        .onChange(of: enableModelName) { enabled in if enabled { applyModelName() } else { removeModelName() } }
        .onChange(of: modelName) { _ in if enableModelName && !modelName.isEmpty { applyModelName() } }
        .onChange(of: enableCustomSubtype) { enabled in
            if enabled {
                dynamicIslandType = -1
                applyCustomSubtype()
            }
        }
        .onChange(of: customSubtypeValue) { _ in
            if enableCustomSubtype { applyCustomSubtype() }
        }
    }

    private func hydrateFromDict() {
        // Reset mặc định trước khi load
        dynamicIslandType = 0
        enableCustomSubtype = false
        customSubtypeValue = ""
        enableModelName = false
        modelName = ""
        productType = MobileGestaltView.machineName()

        if let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
            productType = cacheExtra[MGKey.prodType] as? String ?? productType
            if let artwork = cacheExtra[MGKey.artwork] as? NSDictionary, let subtype = artwork["ArtworkDeviceSubType"] as? Int {
                switch subtype {
                case 2436: dynamicIslandType = 1
                case 2556: dynamicIslandType = 2
                case 2796: dynamicIslandType = 3
                case 2976: dynamicIslandType = 4
                case 2622: dynamicIslandType = 5
                case 2868: dynamicIslandType = 6
                case 2736: dynamicIslandType = 7
                default:
                    dynamicIslandType = -1
                    enableCustomSubtype = true
                    customSubtypeValue = "\(subtype)"
                }
            }
            if let artwork = cacheExtra[MGKey.artwork] as? NSDictionary, let name = artwork["ArtworkDeviceProductDescription"] as? String, !name.isEmpty {
                enableModelName = true
                modelName = name
            }
        }
    }

    @ViewBuilder private var enableSection: some View {
        Section(header: Text(L("tool_mobile_gestalt"))) {
            Toggle(L("enable_tweak"), isOn: $toolStore.replaceMobileGestaltEnabled)
                .onChange(of: toolStore.replaceMobileGestaltEnabled) { isEnabled in
                    if !isEnabled { showApplyTab = false }
                }
        }
    }

    @ViewBuilder private var deviceSubtypeSection: some View {
        Section(header: Text(L("section_device_subtype"))) {
            Picker(selection: $dynamicIslandType) {
                Text(L("mg_subtype_none")).tag(0)
                Text(L("mg_subtype_2436")).tag(1)
                Text(L("mg_subtype_2796")).tag(3)
                Text(L("mg_subtype_2976")).tag(4)
                Text(L("mg_subtype_2622")).tag(5)
                Text(L("mg_subtype_2868")).tag(6)
                Text(L("mg_subtype_2736")).tag(7)
                Text("Custom Subtype").tag(-1) // Thêm option custom
            } label: {
                MGIconPickerLabel(title: L("mg_device_subtype_preset"), systemImage: "iphone")
            }
            .pickerStyle(.menu)
            .onChange(of: dynamicIslandType) { newValue in
                if newValue != -1 {
                    enableCustomSubtype = false
                    _ = store.applyDynamicIsland(type: newValue)
                } else {
                    enableCustomSubtype = true
                }
            }

            // Custom Subtype UI
            if enableCustomSubtype {
                Toggle("Enable Custom Subtype", isOn: $enableCustomSubtype)
                if enableCustomSubtype {
                    TextField("Enter ArtworkDeviceSubType (e.g. 3000)", text: $customSubtypeValue)
                        .keyboardType(.numberPad)
                }
            }

            Toggle(isOn: $enableModelName) {
                Text(L("mg_change_model_name"))
            }
            if enableModelName {
                TextField(L("mg_model_name_placeholder"), text: $modelName)
            }
        }
    }

    @ViewBuilder private var hardwareFeaturesSection: some View {
        Section(header: Text(L("section_hardware_features"))) {
            IconToggle(title: L("mg_boot_chime"), systemImage: "speaker.wave.2.fill", isOn: store.mgByteBinding(key: MGKey.bootChime))
            IconToggle(title: L("mg_charge_limit"), systemImage: "battery.100percent.bolt", isOn: store.mgByteBinding(key: MGKey.chargeLim))
                .disabled(Utils.requiresVersion(17))
            if UIDevice._hasHomeButton() {
                IconToggle(title: L("mg_tap_to_wake"), systemImage: "hand.tap.fill", isOn: store.mgByteBinding(key: MGKey.tapToWake))
            }
            IconToggle(title: L("mg_camera_button"), systemImage: "camera.fill", isOn: store.mgByteBinding(key: MGKey.camButton))
                .disabled(Utils.requiresVersion(18))
        }
    }

    @ViewBuilder private var displayAndUISection: some View {
        Section(header: Text(L("section_display_and_ui"))) {
            IconToggle(title: L("mg_stage_manager"), systemImage: "rectangle.on.rectangle.angled", isOn: store.mgByteBinding(key: MGKey.stageMgr))
            IconToggle(title: L("mg_aod"), systemImage: "moon.stars.fill", isOn: store.mgByteBinding(key: MGKey.aod))
                .disabled(Utils.requiresVersion(18))
            IconToggle(title: L("mg_aod_vibrancy"), systemImage: "circle.lefthalf.filled", isOn: store.mgByteBinding(key: MGKey.aodVibrancy))
                .disabled(Utils.requiresVersion(18))
            Toggle(isOn: store.mgTrollPadBinding()) {
                HStack(spacing: 12) {
                    CleanTweakIcon(systemImage: "ipad.and.iphone")
                    Text("Become iPadOS")
                }
            }
        }
    }

    @ViewBuilder private var systemFeaturesSection: some View {
        Section(header: Text(L("section_system_features"))) {
            Toggle(isOn: bindingForMGKeys(["9MZ5AdH43csAUajl/dU+IQ"], type: [Int].self, defaultValue: [1], enableValue: [1, 2])) {
                HStack(spacing: 12) {
                    CleanTweakIcon(systemImage: "square.grid.2x2.fill")
                    Text(L("mg_install_ipad_apps"))
                }
            }
            Toggle(isOn: store.mgRegionRestrictionsBinding()) {
                HStack(spacing: 12) {
                    CleanTweakIcon(systemImage: "globe")
                    Text(L("mg_disable_region"))
                }
            }
            IconToggle(title: L("mg_apple_pencil"), systemImage: "applepencil", isOn: store.mgByteBinding(key: MGKey.appPencil))
            IconToggle(title: L("mg_action_button"), systemImage: "button.horizontal.top.press", isOn: store.mgByteBinding(key: MGKey.actButton))
                .disabled(Utils.requiresVersion(17))
            IconToggle(title: L("mg_crash_detection"), systemImage: "car.side.rear.and.collision.and.car.side.front", isOn: store.mgByteBinding(key: MGKey.crashDet))
        }
    }

    @ViewBuilder private var advancedSection: some View {
        Section(header: Text(L("section_internal_features"))) {
            IconToggle(title: L("mg_internal_storage"), systemImage: "internaldrive.fill", isOn: store.mgByteBinding(key: MGKey.intBuild))
            IconToggle(title: L("mg_internal_stuff"), systemImage: "wrench.and.screwdriver.fill", isOn: store.mgByteBinding(key: MGKey.intInstall))
            IconToggle(title: L("mg_security_research"), systemImage: "terminal", isOn: store.mgByteBinding(key: MGKey.srd))
            Toggle(isOn: bindingForAppleIntelligence()) {
                HStack(spacing: 12) {
                    CleanTweakIcon(systemImage: "apple.intelligence")
                    Text(L("mg_apple_intelligence"))
                }
            }
            .disabled(Utils.requiresVersion(18))
            Picker(selection: $productType) {
                Text(L("mg_device_model_unchanged")).tag(MobileGestaltView.machineName())
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Text("iPad Pro 11 inch 5th Gen").tag("iPad16,3")
                } else {
                    Text("iPhone 15 Pro Max").tag("iPhone16,2")
                    Text("iPhone 16 Pro Max").tag("iPhone17,2")
                }
            } label: {
                MGIconPickerLabel(title: L("mg_device_model"), systemImage: "iphone.gen3")
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder private var saveResetSection: some View {
        Section(header: Text(L("section_save_reset"))) {
            Button(action: saveChanges) {
                Label(L("mg_save_settings"), systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive, action: resetOriginal) {
                Label("Reset Original", systemImage: "arrow.counterclockwise")
            }
        }
    }

    private func applyCustomSubtype() {
        if let val = Int(customSubtypeValue) {
            _ = store.applyDynamicIsland(type: -1, customValue: val)
        }
    }

    private func saveChanges() {
        do {
            let onDeviceURL = URL(fileURLWithPath: MobileGestaltApplyTask.onDeviceMGPath)
            if let originalData = try? Data(contentsOf: onDeviceURL) {
                try? MobileGestaltBackupManager.shared.ensureBackup(from: originalData)
            }
            saveProductType()
            if let storeCacheExtra = store.mgCurrentDict["CacheExtra"] as? NSMutableDictionary,
               let localCacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
                for (key, value) in storeCacheExtra { localCacheExtra[key as! String] = value }
            }
            if let storeCacheData = store.mgCurrentDict["CacheData"] {
                mobileGestalt["CacheData"] = storeCacheData
            }
            try mobileGestalt.write(to: modMGURL)
            store.loadFromPlist(url: modMGURL)
            showApplyTab = true
            lastError = "Đã lưu. Tab Apply đã mở."
            showErrorAlert = true
        } catch {
            lastError = "Save failed: \(error)"
            showErrorAlert = true
        }
    }

    // SỬA LẠI: Xoá sạch key cũ, reset UI, load lại nguyên bản từ backup
    private func resetOriginal() {
        do {
            // 1. Lấy dữ liệu backup nguyên bản
            let pristineData: Data
            if MobileGestaltBackupManager.shared.hasBackup {
                pristineData = try MobileGestaltBackupManager.shared.restoreData()
            } else {
                // Nếu chưa có backup, lấy file hệ thống gốc làm chuẩn
                pristineData = try Data(contentsOf: URL(fileURLWithPath: MobileGestaltApplyTask.onDeviceMGPath))
            }
            
            guard pristineData.count > 0 else {
                throw NSError(domain: "Reset", code: -1, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu backup bị rỗng! Không thể khôi phục."])
            }

            // 2. Ghi đè lên file local
            try pristineData.write(to: modMGURL)
            
            // 3. Load lại từ file local vào State & Store
            let freshDict = try NSMutableDictionary(contentsOf: modMGURL, error: ())
            self.mobileGestalt = freshDict
            
            store.mgCurrentDict = freshDict
            store.objectWillChange.send()
            
            // 4. Reset cứng UI
            dynamicIslandType = 0
            enableCustomSubtype = false
            customSubtypeValue = ""
            enableModelName = false
            modelName = ""
            
            // 5. Hydrate lại (để lấy đúng dữ liệu nếu file pristine có sẵn tweaks)
            hydrateFromDict()
            
            showApplyTab = true
            lastError = "Đã khôi phục về nguyên bản, xoá sạch key cũ. Bấm Apply để ghi đè lên thiết bị."
            showErrorAlert = true
        } catch {
            lastError = "Reset failed: \(error)"
            showErrorAlert = true
        }
    }

    init(toolStore: ToolStore) {
        self.toolStore = toolStore
        let docs = URL.documentsDirectory
        featFlagsURL   = docs.appendingPathComponent("FeatureFlags.plist", conformingTo: .data)
        origMGURL      = docs.appendingPathComponent("OriginalMobileGestalt.plist", conformingTo: .data)
        modMGURL       = docs.appendingPathComponent("ModifiedMobileGestalt.plist", conformingTo: .data)
        resolutionURL  = docs.appendingPathComponent("Resolution.plist", conformingTo: .data)
        do {
            if !FileManager.default.fileExists(atPath: origMGURL.path) {
                let url = URL(filePath: MobileGestaltApplyTask.onDeviceMGPath)
                try FileManager.default.copyItem(at: url, to: origMGURL)
            }
            chmod(origMGURL.path, 0o644)
            if !FileManager.default.fileExists(atPath: modMGURL.path) {
                try FileManager.default.copyItem(at: origMGURL, to: modMGURL)
            }
            chmod(modMGURL.path, 0o644)
            _mobileGestalt = State(initialValue: try NSMutableDictionary(contentsOf: modMGURL, error: ()))
        } catch {
            _mobileGestalt = State(initialValue: [:])
            _initError = State(initialValue: "Failed to copy MobileGestalt: \(error)")
            taskRunning = true
        }
    }

    func bindingForAppleIntelligence() -> Binding<Bool> {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return .constant(false) }
        let key = MGKey.appIntell
        return Binding(
            get: { (cacheExtra[key] as? Int) == 1 },
            set: { enabled in
                if enabled {
                    if let url = Bundle.main.url(forResource: "eligibility", withExtension: "plist"),
                       let data = try? Data(contentsOf: url) { eligibilityData = data }
                    if let url = Bundle.main.url(forResource: "FeatureFlags_Global", withExtension: "plist"),
                       let data = try? Data(contentsOf: url) { featureFlagsData = data }
                    cacheExtra[key] = 1
                } else {
                    featureFlagsData = (try? PropertyListSerialization.data(fromPropertyList: [:], format: .xml, options: 0)) ?? Data()
                    eligibilityData = featureFlagsData
                    cacheExtra.removeObject(forKey: key)
                }
            }
        )
    }

    func bindingForMGKeys<T: Equatable>(_ keys: [String], type: T.Type = Int.self, defaultValue: T? = 0, enableValue: T? = 1) -> Binding<Bool> {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return .constant(false) }
        return Binding(
            get: {
                guard let value = cacheExtra[keys.first!] as? T, let ev = enableValue else { return false }
                return value == ev
            },
            set: { enabled in
                for key in keys {
                    if enabled { cacheExtra[key] = enableValue } else { cacheExtra.removeObject(forKey: key) }
                }
            }
        )
    }

    static func machineName() -> String {
        var sys = utsname()
        uname(&sys)
        return Mirror(reflecting: sys.machine).children.reduce("") { id, el in
            guard let v = el.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
    }

    func saveProductType() {
        if let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary {
            cacheExtra[MGKey.prodType] = productType
        }
    }

    func applyModelName() {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return }
        let dict = (cacheExtra[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
        dict["ArtworkDeviceProductDescription"] = modelName
        cacheExtra[MGKey.artwork] = dict
        store.cacheExtra[MGKey.artwork] = dict
        store.objectWillChange.send()
    }

    func removeModelName() {
        guard let cacheExtra = mobileGestalt["CacheExtra"] as? NSMutableDictionary else { return }
        if let g = cacheExtra[MGKey.artwork] as? NSMutableDictionary {
            g.removeObject(forKey: "ArtworkDeviceProductDescription")
        }
        if let s = store.cacheExtra[MGKey.artwork] as? NSMutableDictionary {
            s.removeObject(forKey: "ArtworkDeviceProductDescription")
        }
    }
}