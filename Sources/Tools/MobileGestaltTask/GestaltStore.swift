//
//  GestaltStore.swift
//  EnsWilde
//

import SwiftUI
import Combine
import CoreFoundation
import MachO

enum MGURL {
    static let fsGestaltURL = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist")
    static let savedGestaltURL = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.plist")
    static let savedGestaltSHA256URL = URL.documentsDirectory.appendingPathComponent("OriginalGestalt.sha256")
    static let preApplyGestaltURL = URL.documentsDirectory.appendingPathComponent("PreApplyGestalt.plist")
    static let systemVaultGestaltURL = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/.erosion_factory_vault.plist")
    static let systemVaultSHA256URL = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/.erosion_factory_vault.sha256")
}

enum MGRegionUnlockMode: String, CaseIterable, Identifiable {
    case fullUS = "full_us"
    case regionCodeOnly = "ll_only"
    static let defaultsKey = "mgRegionUnlockMode"
    var id: String { rawValue }
}

enum MGMsg {
    static var region: String { L("开启后默认把销售地区改为完整美版 (LL + LL/A) 并映射对应美版监管型号 (Axxxx)；你也可在下方子选项切换为「仅改区域代码 LL（保留 CH/A 后缀与双卡兼容）」。请遵守当地法律法规并自行承担使用风险。") }
    static var regionModeInfo: String { L("【地区修改模式细化说明】\n\n1. 完整美版 LL + LL/A（默认）：\n同时将区域代码改为 LL、系统销售地区改为 LL/A，并自动填入对应的美版监管型号 (Axxxx)，跨区域受限特性（海外版 Apple 智能、快门静音、健康区域特性等）一致性最完整。\n\n2. 仅改区域代码 LL（保留 CH/A 后缀与双卡兼容）：\n仅将区域代码 (RegionCode) 改为 LL，完整保留原机的销售地区后缀（如 CH/A）与原厂监管型号。既可满足基础 Apple 智能准入、让「设置 -> 关于本机」型号末尾继续显示 CH/A，也能避免国行双实体卡槽 + eSIM 机型（如 18 Pro / Pro Max）因映射无卡槽美版型号引发基带卡槽冲突。") }
    static var ipadOS: String { L("如果你当前设置了字母数字混合锁屏密码，请切勿开启此项！开启后也切勿关闭“在台前调度中显示程序坞”，否则会导致设备软砖（白苹果循环）。启用 iPadOS 界面后可能出现界面错位、部分应用不兼容等问题。") }
    static var support: String { L("请提前备份重要数据！如果某项修改未按预期生效，请勿向官方仓库提交支持请求。许多功能同时受限于设备硬件与 Apple 服务器策略，所有修改均需自行承担风险。") }
    static var mgReset: String { L("重置 MobileGestalt 将删除系统原始缓存文件并让系统在重启时重新生成。这有助于彻底清除无法还原的修改，但存在极低概率引发异常，请谨慎操作。") }
    static var liquidGlass: String { L("开启后将使用 iOS 26/27 液态玻璃 (Liquid Glass) 的低性能开销渲染模式，可降低 GPU 负载、减少机身发热并节省电量（注销或重启后生效）。") }
    static var chinaCacheUnlock: String { L("通过从本机内存加载的系统库 (libMobileGestalt.dylib) 实时动态解析二进制 CacheData 槽位偏移，将国行底层限制标记 green-tea 设为 false、not-green-tea 设为 true。") }
    static var wapiToWifi: String { L("通过本机系统库实时动态解析 wapi 布尔槽位偏移并设为 false，将系统“设置”与控制中心里的“无线局域网”统一显示为国际版的“Wi-Fi”。") }
    static var intInstall: String { L("此选项将启用部分遗留在正式版 iOS 中的 Apple 内部调试特性。注意：开启后可能会影响部分正常功能（如无法从 App Store 重新安装自带系统应用），且与 Apple 智能互斥。") }
    static var intBuild: String { L("此开关主要用于在“设置”应用中显示内部存储调试信息。在部分设备（尤其是 iPadOS）上可能引发兼容性问题。") }
    static var appleIntellInfo: String { L("为不支持 Apple 智能的旧机型开启端侧生成式 AI 总开关 (DeviceSupportsGenerativeModelSystems)") }
    static var advAppleIntell: String { L("【防呆护栏警告】真机（iPhone 15 Pro Max 与 iPhone 18 Pro Max）底层探针交叉核验确认：iOS 27 音频智能在 iPhone / iPad 原厂设备树中默认均为 false。") }
    static var audioMixInfo: String { L("通过本机系统库实时动态解析 CameracinematicAudioTrackRendering 二进制 CacheData 布尔槽位并设为 true，解锁相册与相机视频编辑中的“混音 (Audio Mix)”功能。") }
    static var spatialAudioInfo: String { L("通过本机系统库实时动态解析 spatial-audio-recording 与 spatial-facetime-audio 二进制 CacheData 布尔槽位。") }
    static var spatialFaceTimeInfo: String { L("通过本机系统库实时动态解析 spatial-facetime-audio 二进制 CacheData 布尔槽位。") }
    static var spatialAudioRecInfo: String { L("通过本机系统库实时动态解析 spatial-audio-recording 二进制 CacheData 布尔槽位。") }
    static var responsiveShutterInfo: String { L("通过本机系统库实时动态解析 ResponsiveShutter 二进制 CacheData 布尔槽位并设为 true。") }
    static var hypertensionInfo: String { L("通过本机系统库实时动态解析 HypertensionNotifications 二进制 CacheData 布尔槽位并设为 true。") }
    static var callScreeningGuide: String { L("【普通话“询问来电原因”与海外 Apple 智能黄金共存方案（测试特性）】") }
    static var expNotice: String { L("【测试特性提示】本分组所有开关均通过运行时从本机 libMobileGestalt.dylib 实时解析真实 CacheData 布尔槽位。") }
    static var expShutterMuteInfo: String { L("【测试特性】传统 RegionalBehaviorShutterClick 为只读动态探针。") }
    static var expStudioMicsInfo: String { L("【测试特性】开启高低功耗双阵列麦克风并发拾音槽位。") }
    static var expPhotoToneInfo: String { L("【测试特性】同步开启 PhotosLocalLight、ToneMapping 与 HDRDeferredProcessing 三个影像后期管线布尔槽位。") }
    static var expSpatialStereoInfo: String { L("【测试特性】同步开启 SpatialOverCapture、StereoAudioRecording 与 P3ColorspaceVideoRecording 三个视频捕获槽位。") }
    static var expCamControlInfo: String { L("【测试特性】同步开启 CameraButtonCapability、TouchSensitiveCameraControl、HardwareDetents 与 CameraHaptics 四个交互槽位。") }
    static var expLegacyBatteryInfo: String { L("【测试特性】开启 DeviceShowsBatteryModelInformationLegacyHW 与 DynamicEndOfChargeLegacyHW 槽位。") }
    static var expHighLumAODInfo: String { L("【测试特性】同步开启 HighLuminanceAlwaysOnDisplay 与 AlwaysOnDisplayFlipbook 槽位。") }
    static var expCarPlay2Info: String { L("【测试特性】开启 DeviceSupportsCarPlay2 槽位。") }
    static var expTouch120Info: String { L("【测试特性】开启 TouchDelivery120Hz 槽位。") }
    static var expHearingAidInfo: String { L("【测试特性】同步开启 hearingaid-audio-equalization、hearingaid-low-energy-audio 与 hearingaid-power-reduction 三个连续布尔槽位。") }
    static var expSleepApneaInfo: String { L("【测试特性】开启 DeviceSupportsBreathingDisturbancesMeasurements 槽位。") }
    static var expUSBloodOxygenInfo: String { L("【测试特性】将 DeviceSupportsUSLegallyCompliantBloodOxygen 槽位设为 false。") }
    static var expWorkoutUltraInfo: String { L("【测试特性】同步开启 WorkoutUltraMode 与 DeviceSupportsTimeInDaylight 槽位。") }
    static var expSiriHubInfo: String { L("【防呆护栏警告】真机实测表明：DeviceSupportsSiriHub 属于带屏家居中枢硬件专属路由标记。") }
    static var spoofUseless: String { L("伪装设备型号可能会导致面容 ID (Face ID) 等硬件功能失效！你的设备硬件本身已原生支持 Apple 智能。") }
    static var spoofAI: String { L("对于不支持 Apple 智能的旧机型，仅开启开关无法下载端侧 AI 模型，还需伪装为支持的机型；但伪装机型可能导致面容 ID 失效。") }
    static var subtype: String { L("仅在你想调整灵动岛纵向位置或屏幕分辨率特征时才修改设备子类型 (Subtype)。") }
    static var mgResetComp: String { L("已移除当前 MobileGestalt 缓存并将旧备份安全归档。请立即【手动重启你的设备】。") }
    static var revertComp: String { L("已通过 SHA-256 与物理落盘校验恢复本机原厂备份。建议【手动重启一次手机】。") }
    static var revertConfirm: String { L("即将执行本机原厂参数恢复。") }
    static var globalFactoryRestoreConfirm: String { L("即将执行全模块一键恢复原机出厂参数。") }
    static var mgResetSavWarn: String { L("重新生成原始备份前，请确保当前已还原所有修改。") }
    static var hidTweakWarn: String { L("显示被隐藏的修改项后，你将能看到当前机型本已原生支持或不兼容的底层开关。") }
}

enum MGKey {
    static let ipadosCacheEx = [
        "uKc7FPnEO++lVhHWHFlGbQ", "mG0AnH/Vy1veoqoLRAIgTA", "UCG5MkVahJxG1YULbbd5Bg",
        "ZYqko/XM5zD3XBfN5RmaXA", "nVh/gwNpy7Jv1NOk00CMrw", "qeaj75wk3HF4DwQ8qbIi7g"
    ]
    static let deviceClassNumber = "mtrAoWJ3gsq+I90ZnQ0vQw"
    static let island = "YlEtTtHlNesRBMal1CqRaA"
    static let AOTime = "j8/Omm6s1lsmTDFsXjsBfA"
    static let AOD = "2OOJf1VhaM7NxfRok3HbWQ"
    static let AODVibrancy = "ykpu7qyhqFweVMKtxNylWA"
    static let liquidGlassLowPower = "SAGvsp6O6kAQ4fEfDJpC4Q"
    static let chargeLim = "37NVydb//GP/GrhuTN+exg"
    static let bootChime = "QHxt+hGLaBPbQJbXiUJX3w"
    static let intInstall = "EqrsVvjcYDdxHBiQmGhAWw"
    static let intBuild = "LBJfwOEzExRxzlAnSuI7eg"
    static let srd = "XYlJKKkj2hztRP1NWWnhlw"
    static let appIntell = "A62OafQ85EJAiiqKn4agtg"
    static let photosCleanUp = "XNCjqOupLM/S8fNyxRNQTA"
    static let handwritingSynth = "YgYIIViDt1kgzyIsIV61vA"
    static let appIntellAllKeys = ["A62OafQ85EJAiiqKn4agtg", "XNCjqOupLM/S8fNyxRNQTA", "YgYIIViDt1kgzyIsIV61vA"]
    static let audioIntell = "rb2tKZxlj0Gm2tBmUQSLqQ"
    static let personalTranslator = "M1n2sAqf33NAOgZRGxQYBA"
    static let advAppIntellKeys = ["rb2tKZxlj0Gm2tBmUQSLqQ", "M1n2sAqf33NAOgZRGxQYBA"]
    static let advAppIntellRules: [MGSlotRule] = [
        MGSlotRule(key: "rb2tKZxlj0Gm2tBmUQSLqQ", targetValue: true, required: false),
        MGSlotRule(key: "M1n2sAqf33NAOgZRGxQYBA", targetValue: true, required: false)
    ]
    static let regionCode = "h63QSdBCiT/z0WU6rdQv6Q"
    static let regionInfo = "zHeENZu+wbg7PUprwNwBWg"
    static let regionSysconfig = "yK+xavymRGZ3xWc1tb8XDg"
    static let regModelNumber = "97JDvERpVwO+GHtthIh7hA"
    static let audioMix = "aVL5GE3tx0LSCI/ErfrJGA"
    static let spatialAudioRec = "X6NGcYcvHmbqlR8hLXASJA"
    static let spatialFaceTimeAudio = "/EVOCjM/Nmb2roP5ebtEFA"
    static let spatialAudioAllKeys = ["X6NGcYcvHmbqlR8hLXASJA", "/EVOCjM/Nmb2roP5ebtEFA"]
    static let responsiveShutter = "gQDt76Te0SPw7N8oTLrBFw"
    static let hypertensionNotif = "4fh9efw4o1yaFqkXNCXoeA"
    static let mediaHealthAllKeys = ["aVL5GE3tx0LSCI/ErfrJGA", "X6NGcYcvHmbqlR8hLXASJA", "/EVOCjM/Nmb2roP5ebtEFA", "gQDt76Te0SPw7N8oTLrBFw", "4fh9efw4o1yaFqkXNCXoeA"]
    static let crashDet = "HCzWusHQwZDea6nNhaKndw"
    static let pwm = "6IejgN+1Fmu5/QrZFOIeNw"
    static let appPencil = "yhHcB0iH0d1XzPO/CFd3ow"
    static let camButton = "CwvKxM2cEogD3p+HYgaW0Q"
    static let grapPefr = "oOV1jhJbdV3AddkcCg0AEA"
    static let actButton = "cT44WE1EohiwRzhsZ8xEsw"
    static let tapToWake = "yZf3GTRMGTuwSV/lD7Cagw"
    static let stageMgr = "qeaj75wk3HF4DwQ8qbIi7g"
    static let deviceClass = "+3Uf0Pm5F8Xy7Onyvko0vA"
    static let artwork = "oPeik/9e8lQWMszEjbPzng"
    static let prodType = "h9jDsbgj7xIVeIQ8S3/X3Q"
    static let modelNameOuter1 = "Z/dqyWS6OZTRy10UcmUAhw"
    static let modelNameOuter2 = "bbtR9jQx50Fv5Af/affNtA"
    static let shutterRelaxation = "P4ZJVy/zYuLy4ejRKP+0DA"
    static let shutterKeyboardMutePreserve = "bGUN8lS6sYzy3xhePubp8A"
    static let shutterLegacyMutePreserve = "Bim3FC83Te8QX1kfSpqYKQ"
    static let concurrentHPLPMics = "dI30ovtFUIeLioNQKDMbGQ"
    static let photosLocalLight = "m9ORTKMgu9A+zF+A61Zz5A"
    static let toneMapping = "Lcu6Zck+C/+AMO8qULacDw"
    static let hdrDeferredProcessing = "JkZlE8z9YwHjE1hnbMhcgA"
    static let spatialOverCapture = "SjQQ07G8UacM7E69G7dPbg"
    static let stereoAudioRec = "YlK+0xmxNWhNn/+r8SM8kA"
    static let p3VideoRec = "1eBwtCIwbIDdC80wiyzfow"
    static let touchSensitiveCamControl = "lyJZrSDc8J8eQ5Zb7A1Rvw"
    static let hardwareDetents = "V9pLLbPQhyb75bbdTioZVw"
    static let cameraHaptics = "XriAxQ+JY1z5nt5f3ftXVw"
    static let legacyBatteryInfo = "Rq0MF/w+gXM66Ii4fkWOzg"
    static let legacyDynamicEndOfCharge = "nfR1IphTGCaoFNu3NrCtWQ"
    static let highLuminanceAOD = "7brdL5xrEUWnlF9C0kdg5A"
    static let aodFlipbook = "aoJSd/MXk7M40NgXTM6x+g"
    static let carPlay2 = "PR+xeEtTAiUN0R25+EYGfw"
    static let touchDelivery120Hz = "2OK50OGmkXM1ospsh766WQ"
    static let hearingAidEQ = "SMgTCc2v9AU2ziIHRX8qww"
    static let hearingAidLE = "RyXm3yMC4ejlFvwlEI509w"
    static let hearingAidPowerRed = "u3c0R+31Df4SUTHrICQkTg"
    static let breathingDisturbances = "e0HV2blYUDBk/MsMEQACNA"
    static let usBloodOxygen = "E4vGMChwcVRKD8hMVxnRvg"
    static let workoutUltra = "fu+4kyf8VcMBtgbMyJlLtg"
    static let timeInDaylight = "8gVfz9/8R1OtWBBtI0o/+Q"
    static let siriHub = "waGD2UTpntjbDXD1r3oALQ"
    static let onDeviceSiri = "O/7gbXWA5X2IRPVtDRU+bw"
    static let modelPruning = "m4xs4mhvxnAopYrApoLDMw"
    static let experimentalCacheSlotKeys: [String] = [
        shutterRelaxation, shutterKeyboardMutePreserve, shutterLegacyMutePreserve, concurrentHPLPMics,
        photosLocalLight, toneMapping, hdrDeferredProcessing, spatialOverCapture, stereoAudioRec, p3VideoRec,
        touchSensitiveCamControl, hardwareDetents, cameraHaptics, legacyBatteryInfo, legacyDynamicEndOfCharge,
        highLuminanceAOD, aodFlipbook, carPlay2, touchDelivery120Hz, hearingAidEQ, hearingAidLE, hearingAidPowerRed,
        breathingDisturbances, usBloodOxygen, workoutUltra, timeInDaylight, siriHub, onDeviceSiri, modelPruning
    ]
}

struct MGSlotRule: Equatable {
    let key: String
    let targetValue: Bool
    var required: Bool = true
}

final class GestaltStore: ObservableObject {
    static let shared = GestaltStore()
    
    @Published var mgCurrentDict = NSMutableDictionary()
    var cacheExtra: NSMutableDictionary {
        return mgCurrentDict["CacheExtra"] as? NSMutableDictionary ?? NSMutableDictionary()
    }
    
    init() {}
    
    func originalCacheExtraValue(forKey key: String) -> Any? {
        guard let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL), let ogCacheExtra = ogDict["CacheExtra"] as? NSDictionary else { return nil }
        return ogCacheExtra[key]
    }
    
    func restoreOrRemoveKey(_ key: String) {
        if let ogVal = originalCacheExtraValue(forKey: key) { self.cacheExtra[key] = ogVal } else { self.cacheExtra.removeObject(forKey: key) }
    }
    func disableBooleanExtraKey(_ key: String, enableValue: Int = 1) {
        if let ogVal = originalCacheExtraValue(forKey: key) {
            if let ogNum = ogVal as? NSNumber, ogNum.intValue == enableValue { self.cacheExtra.removeObject(forKey: key) } else { self.cacheExtra[key] = ogVal }
        } else { self.cacheExtra.removeObject(forKey: key) }
    }
    func mgPullKeys(_ keys: [String], enableValue: Int = 1) { for key in keys { disableBooleanExtraKey(key, enableValue: enableValue) } }
    
    func isKeyEnabled(_ key: String, enableValue: Int = 1) -> Bool {
        if let num = self.cacheExtra[key] as? NSNumber, num.intValue == enableValue { return true }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict),
           let slotIdx = layout.slotIndex(forKey: key), layout.validateSingleBooleanSlot(slotIdx, in: data), data[slotIdx * 8] == 1 {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
            if !origVal { return true }
        }
        return false
    }

    func isEnabled(_ keys: [String], enableValue: Int = 1) -> Bool { guard !keys.isEmpty else { return false }; return keys.allSatisfy { self.isKeyEnabled($0, enableValue: enableValue) } }
    func strVal(forKey key: String) -> String { return self.cacheExtra[key] as? String ?? "" }
    
    func mgKeyBinding(_ keys: [String], defaultValue: Int = 0, enableValue: Int = 1) -> Binding<Bool> {
        return Binding(get: {
            guard !keys.isEmpty else { return false }
            return keys.allSatisfy { self.isKeyEnabled($0, enableValue: enableValue) }
        }, set: { enabled in
            self.objectWillChange.send()
            for key in keys { if enabled { self.cacheExtra[key] = enableValue } else { self.disableBooleanExtraKey(key, enableValue: enableValue) } }
            if case .success((let layout, var data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                var touchedSlot = false
                for key in keys {
                    if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                        if enabled { data[slotIdx * 8] = (enableValue != 0) ? 1 : 0 } else {
                            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                        touchedSlot = true
                    }
                }
                if touchedSlot {
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    testDict["CacheData"] = data
                    if case .success = layout.validatePlist(testDict) { self.mgCurrentDict["CacheData"] = data }
                }
            }
        })
    }
    
    func mgTrollPadBinding() -> Binding<Bool> {
        return Binding(get: {
            guard let firstKey = MGKey.ipadosCacheEx.first else { return false }
            return (self.cacheExtra[firstKey] as? NSNumber)?.intValue == 1
        }, set: { enabled in
            self.objectWillChange.send()
            _ = self.mgSetiPadOS(enable: enabled)
        })
    }
    
    func mgSetiPadOS(enable: Bool) -> Bool {
        guard let cacheData = mgCurrentDict["CacheData"] as? Data else {
            print("❌ Lỗi: Không đọc được CacheData")
            return false
        }

        let ipadKeys = MGKey.ipadosCacheEx
        let deviceClassKey = MGKey.deviceClassNumber

        guard case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() else {
            print("❌ Lỗi: Không thể phân giải layout từ libMobileGestalt")
            return false
        }

        var patchedData = cacheData
        var patchedCount = 0

        // Vá 6 key Medusa (Bật đa nhiệm, Stage Manager)
        for key in ipadKeys {
            if let slotIdx = layout.slotIndex(forKey: key) {
                let offset = slotIdx * 8
                if offset + 8 <= patchedData.count {
                    patchedData[offset] = enable ? 0x01 : 0x00
                    for i in 1..<8 { patchedData[offset + i] = 0x00 }
                    patchedCount += 1
                }
            } else {
                print("⚠️ Không tìm thấy slot cho key \(key)")
            }
        }

        // Vá DeviceClassNumber (1 = iPhone, 3 = iPad)
        // Lưu ý: Có thể không tìm thấy trong layout nếu qtype != 11, nên ta không dùng nó làm điều kiện chặn.
        if let classSlot = layout.slotIndex(forKey: deviceClassKey) {
            let classOffset = classSlot * 8
            if classOffset + 8 <= patchedData.count {
                patchedData[classOffset] = enable ? 0x03 : 0x01
                for i in 1..<8 { patchedData[classOffset + i] = 0x00 }
                patchedCount += 1
            }
        } else {
            print("⚠️ Không tìm thấy slot cho DeviceClassNumber trong layout (có thể do qtype != 11)")
        }

        // Cho phép chạy kể cả khi không tìm thấy DeviceClassNumber, miễn là tìm thấy các key Medusa
        guard patchedCount >= 1 else {
            print("❌ Lỗi: Không vá được slot nào cả.")
            return false
        }

        self.mgCurrentDict["CacheData"] = patchedData
        print("✅ Đã vá thành công \(patchedCount) slot iPadOS vào CacheData.")
        
        // Cập nhật UI state
        for key in ipadKeys {
            if enable { self.cacheExtra[key] = 1 } else { self.cacheExtra.removeObject(forKey: key) }
        }
        return true
    }
    
    var preferredRegionUnlockMode: MGRegionUnlockMode {
        get {
            let raw = UserDefaults.standard.string(forKey: MGRegionUnlockMode.defaultsKey) ?? MGRegionUnlockMode.fullUS.rawValue
            return MGRegionUnlockMode(rawValue: raw) ?? .fullUS
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: MGRegionUnlockMode.defaultsKey)
        }
    }

    var currentRegionUnlockMode: MGRegionUnlockMode {
        if (self.cacheExtra[MGKey.regionCode] as? String) == "LL" {
            return ((self.cacheExtra[MGKey.regionSysconfig] as? String) == "LL/A") ? .fullUS : .regionCodeOnly
        }
        return preferredRegionUnlockMode
    }

    func isConfirmedChinaHardwareFromCacheData() -> Bool {
        let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict, checkWapiSlot: true) {
            if let origFlags = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig) {
                if origFlags.greenTea || origFlags.wapi == true { return true }
            }
            if let wOff = layout.wapiOffset, data[wOff] == 1 { return true }
        }
        return false
    }

    private func restoreNonUSRegionSysconfig() {
        if let ogSys = originalCacheExtraValue(forKey: MGKey.regionSysconfig) as? String, !ogSys.isEmpty {
            if ogSys == "LL/A" && isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionSysconfig] = "CH/A" } else { self.cacheExtra[MGKey.regionSysconfig] = ogSys }
        } else if isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionSysconfig] = "CH/A" } else { self.cacheExtra.removeObject(forKey: MGKey.regionSysconfig) }
    }

    private func restoreNonUSRegulatoryModel() {
        let prodType = originalHardwareProductType()
        if let ogReg = originalCacheExtraValue(forKey: MGKey.regModelNumber) as? String, !ogReg.isEmpty {
            if let usModel = usRegulatoryModelNumber(productType: prodType, originalRegModel: ""), ogReg == usModel, isConfirmedChinaHardwareFromCacheData(), let cnModel = chinaRegulatoryModelNumber(productType: prodType) {
                self.cacheExtra[MGKey.regModelNumber] = cnModel
            } else { self.cacheExtra[MGKey.regModelNumber] = ogReg }
        } else if isConfirmedChinaHardwareFromCacheData(), let cnModel = chinaRegulatoryModelNumber(productType: prodType) {
            self.cacheExtra[MGKey.regModelNumber] = cnModel
        } else { self.cacheExtra.removeObject(forKey: MGKey.regModelNumber) }
    }

    func mgRegionRestrictionsBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: { return self.cacheExtra[MGKey.regionCode] as? String == "LL" },
            set: { enabled in
                self.objectWillChange.send()
                if enabled {
                    Alertinator.shared.alert(title: L("解除地区限制提示"), body: MGMsg.region)
                    self.applyRegionUnlock(mode: self.preferredRegionUnlockMode)
                } else {
                    if let ogCode = self.originalCacheExtraValue(forKey: MGKey.regionCode) as? String, !ogCode.isEmpty {
                        if ogCode == "LL" && self.isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionCode] = "CH" } else { self.cacheExtra[MGKey.regionCode] = ogCode }
                    } else if self.isConfirmedChinaHardwareFromCacheData() { self.cacheExtra[MGKey.regionCode] = "CH" } else { self.cacheExtra.removeObject(forKey: MGKey.regionCode) }
                    if raveSupported() { self.cacheExtra.removeObject(forKey: MGKey.regionInfo) } else { self.restoreOrRemoveKey(MGKey.regionInfo) }
                    self.restoreNonUSRegionSysconfig()
                    self.restoreNonUSRegulatoryModel()
                }
            }
        )
    }

    func mgRegionUnlockModeBinding() -> Binding<MGRegionUnlockMode> {
        return Binding<MGRegionUnlockMode>(
            get: { return self.currentRegionUnlockMode },
            set: { newMode in
                self.objectWillChange.send()
                self.preferredRegionUnlockMode = newMode
                if (self.cacheExtra[MGKey.regionCode] as? String) == "LL" { self.applyRegionUnlock(mode: newMode) }
            }
        )
    }

    func applyRegionUnlock(mode: MGRegionUnlockMode) {
        self.cacheExtra[MGKey.regionCode] = "LL"
        switch mode {
        case .fullUS:
            self.cacheExtra[MGKey.regionSysconfig] = "LL/A"
            if !raveSupported(), self.originalCacheExtraValue(forKey: MGKey.regionInfo) != nil { self.cacheExtra[MGKey.regionInfo] = "LL/A" } else { self.cacheExtra.removeObject(forKey: MGKey.regionInfo) }
            let prodType = originalHardwareProductType()
            let ogRegModel = (self.originalCacheExtraValue(forKey: MGKey.regModelNumber) as? String) ?? (self.cacheExtra[MGKey.regModelNumber] as? String) ?? ""
            if let usModel = usRegulatoryModelNumber(productType: prodType, originalRegModel: ogRegModel) { self.cacheExtra[MGKey.regModelNumber] = usModel }
        case .regionCodeOnly:
            if raveSupported() { self.cacheExtra.removeObject(forKey: MGKey.regionInfo) } else { self.restoreOrRemoveKey(MGKey.regionInfo) }
            self.restoreNonUSRegionSysconfig()
            self.restoreNonUSRegulatoryModel()
        }
    }

    func applyUSRegionAndRegulatoryModel() { applyRegionUnlock(mode: .fullUS) }
    
    func mgRegModelBinding() -> Binding<String> {
        return Binding<String>(
            get: { return self.cacheExtra[MGKey.regModelNumber] as? String ?? "" },
            set: { newValue in
                self.objectWillChange.send()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { self.restoreOrRemoveKey(MGKey.regModelNumber) } else { self.cacheExtra[MGKey.regModelNumber] = trimmed }
            }
        )
    }

    func canModifyGreenTeaCache() -> Bool { if case .success = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) { return true }; return false }
    func canModifyWapiCache() -> Bool {
        if case .success((let layout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict, checkWapiSlot: true), layout.wapiOffset != nil { return true }
        return false
    }
    func canModifyFeatureSlot(_ keys: [String]) -> Bool {
        guard !keys.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        return keys.allSatisfy { key in guard let slotIdx = layout.featureSlotIndices[key] else { return false }; return layout.validateSingleBooleanSlot(slotIdx, in: data) }
    }
    func isFeatureSlotNativeEnabled(_ keys: [String]) -> Bool {
        guard !keys.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
        return keys.allSatisfy { key in
            guard let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { return false }
            return MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) == true
        }
    }
    func mgFeatureSlotBinding(_ keys: [String], infoTitle: String? = nil, infoMessage: String? = nil) -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard !keys.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) else { return false }
                return keys.allSatisfy { key in
                    guard let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { return false }
                    return data[slotIdx * 8] == 1
                }
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    for key in keys {
                        guard let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) else {
                            Alertinator.shared.alert(title: L("当前系统不支持该槽位！"), body: L("未能在当前系统库与缓存中验证槽位 \(key) 的有效性，已拒绝修改。"))
                            return
                        }
                        if enabled { data[slotIdx * 8] = 1 } else {
                            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for key in keys { testExtra.removeObject(forKey: key) } }
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success:
                        self.objectWillChange.send()
                        for key in keys { self.cacheExtra.removeObject(forKey: key) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }

    func canModifySlotRules(_ rules: [MGSlotRule]) -> Bool {
        guard !rules.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        var matchedCount = 0
        for rule in rules {
            if let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) { matchedCount += 1 } else if rule.required { return false }
        }
        return matchedCount > 0
    }
    func isSlotRulesNativeSatisfied(_ rules: [MGSlotRule]) -> Bool {
        guard !rules.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) else { return false }
        let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
        var resolvedAny = false
        for rule in rules {
            guard let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { if rule.required { return false }; continue }
            resolvedAny = true
            guard let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: rule.key, layout: layout, savedOriginalDict: savedOrig), origVal == rule.targetValue else { return false }
        }
        return resolvedAny
    }
    func mgSlotRulesBinding(_ rules: [MGSlotRule]) -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard !rules.isEmpty, case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) else { return false }
                var resolvedAny = false
                for rule in rules {
                    guard let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) else { if rule.required { return false }; continue }
                    resolvedAny = true
                    let currentBit = (data[slotIdx * 8] == 1)
                    if currentBit != rule.targetValue { return false }
                }
                return resolvedAny
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    var touchedKeys: [String] = []
                    for rule in rules {
                        guard let slotIdx = layout.featureSlotIndices[rule.key], layout.validateSingleBooleanSlot(slotIdx, in: data) else {
                            if rule.required { Alertinator.shared.alert(title: L("当前系统不支持该实验性槽位！"), body: L("未能在当前系统库与缓存中验证槽位 \(rule.key) 的有效性，已拒绝修改。")); return }
                            continue
                        }
                        if enabled { data[slotIdx * 8] = rule.targetValue ? 1 : 0 } else {
                            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: rule.key, layout: layout, savedOriginalDict: savedOrig) ?? (!rule.targetValue)
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                        touchedKeys.append(rule.key)
                    }
                    guard !touchedKeys.isEmpty else { return }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for key in touchedKeys { testExtra.removeObject(forKey: key) } }
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success:
                        self.objectWillChange.send()
                        for key in touchedKeys { self.cacheExtra.removeObject(forKey: key) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }

    func isSiriHubConflictActive() -> Bool {
        if (self.cacheExtra[MGKey.siriHub] as? NSNumber)?.intValue == 1 { return true }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict), let slotIdx = layout.featureSlotIndices[MGKey.siriHub], layout.validateSingleBooleanSlot(slotIdx, in: data), data[slotIdx * 8] == 1 {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            let origVal = MGCacheDataCoordinator.shared.originalSlotValue(forKey: MGKey.siriHub, layout: layout, savedOriginalDict: savedOrig) ?? false
            return !origVal
        }
        return false
    }
    func mgSafeSiriHubGuardrailBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: { return self.isSiriHubConflictActive() },
            set: { enabled in
                if enabled { Alertinator.shared.alert(title: L("安全护栏已拦截冲突开关！"), body: MGMsg.expSiriHubInfo); return }
                let groupKeys = [MGKey.siriHub, MGKey.onDeviceSiri, MGKey.modelPruning]
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure:
                    self.objectWillChange.send()
                    for k in groupKeys { self.disableBooleanExtraKey(k, enableValue: 1) }
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    for k in groupKeys {
                        if let slotIdx = layout.featureSlotIndices[k], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                            let origVal: Bool = (k == MGKey.siriHub) ? false : (MGCacheDataCoordinator.shared.originalSlotValue(forKey: k, layout: layout, savedOriginalDict: savedOrig) ?? false)
                            data[slotIdx * 8] = origVal ? 1 : 0
                        }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for k in groupKeys { testExtra.removeObject(forKey: k) } }
                    testDict["CacheData"] = data
                    if case .success = layout.validatePlist(testDict) {
                        self.objectWillChange.send()
                        for k in groupKeys { self.cacheExtra.removeObject(forKey: k) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }
    func isPersonalTranslatorAccidentallyDisabled() -> Bool {
        guard isNativePersonalTranslatorHD() else { return false }
        if let num = self.cacheExtra[MGKey.personalTranslator] as? NSNumber, num.intValue == 0 { return true }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict), let slotIdx = layout.featureSlotIndices[MGKey.personalTranslator], layout.validateSingleBooleanSlot(slotIdx, in: data), data[slotIdx * 8] == 0 { return true }
        return false
    }
    func isAdvAppleIntellConflictActive() -> Bool {
        if isAdvAppleIntellHD() { return false }
        for key in MGKey.advAppIntellKeys { if self.cacheExtra[key] != nil { return true } }
        if case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            for key in MGKey.advAppIntellKeys {
                if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                    let curVal = (data[slotIdx * 8] == 1)
                    let nativeVal = isAdvAISlotNativeTrue(key, layout: layout, savedOrig: savedOrig)
                    if curVal != nativeVal { return true }
                }
            }
        }
        return false
    }
    func mgSafeAdvAppleIntellGuardrailBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: { return self.isAdvAppleIntellConflictActive() },
            set: { enabled in
                if enabled { Alertinator.shared.alert(title: L("安全护栏已拦截冲突开关！"), body: MGMsg.advAppleIntell); return }
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure:
                    self.objectWillChange.send()
                    for k in MGKey.advAppIntellKeys { self.disableBooleanExtraKey(k, enableValue: 1) }
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    for k in MGKey.advAppIntellKeys {
                        if let slotIdx = layout.featureSlotIndices[k], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                            let nativeVal = isAdvAISlotNativeTrue(k, layout: layout, savedOrig: savedOrig)
                            data[slotIdx * 8] = nativeVal ? 1 : 0
                        }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    if let testExtra = testDict["CacheExtra"] as? NSMutableDictionary { for k in MGKey.advAppIntellKeys { testExtra.removeObject(forKey: k) } }
                    testDict["CacheData"] = data
                    if case .success = layout.validatePlist(testDict) {
                        self.objectWillChange.send()
                        for k in MGKey.advAppIntellKeys { self.cacheExtra.removeObject(forKey: k) }
                        self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }
    func applyAppleIntelligenceOneClickFix() {
        self.objectWillChange.send()
        self.applyRegionUnlock(mode: self.currentRegionUnlockMode)
        self.mgPullKeys([MGKey.intInstall, MGKey.intBuild, MGKey.siriHub] + MGKey.advAppIntellKeys)
        if case .success((let layout, var data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
            let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
            let origFlags = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig)
            let ogRegion = (self.originalCacheExtraValue(forKey: MGKey.regionCode) as? String) ?? ""
            if ogRegion == "CH" || ogRegion == "ZA" || origFlags?.greenTea == true || data[layout.greenTeaOffset] == 1 {
                data[layout.greenTeaOffset] = 0
                data[layout.notGreenTeaOffset] = 1
            }
            if let siriHubSlot = layout.featureSlotIndices[MGKey.siriHub], layout.validateSingleBooleanSlot(siriHubSlot, in: data), data[siriHubSlot * 8] == 1 {
                let origSiriHub = MGCacheDataCoordinator.shared.originalSlotValue(forKey: MGKey.siriHub, layout: layout, savedOriginalDict: savedOrig) ?? false
                if !origSiriHub {
                    data[siriHubSlot * 8] = 0
                    for k in [MGKey.onDeviceSiri, MGKey.modelPruning] {
                        if let idx = layout.featureSlotIndices[k], layout.validateSingleBooleanSlot(idx, in: data) {
                            let origV = MGCacheDataCoordinator.shared.originalSlotValue(forKey: k, layout: layout, savedOriginalDict: savedOrig) ?? false
                            data[idx * 8] = origV ? 1 : 0
                        }
                    }
                }
            }
            if !isAdvAppleIntellHD() {
                for key in MGKey.advAppIntellKeys {
                    if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) {
                        let nativeVal = isAdvAISlotNativeTrue(key, layout: layout, savedOrig: savedOrig)
                        data[slotIdx * 8] = nativeVal ? 1 : 0
                    }
                    self.cacheExtra.removeObject(forKey: key)
                }
            }
            if !isAppleIntellHD() {
                for key in MGKey.appIntellAllKeys {
                    self.cacheExtra[key] = 1
                    if let slotIdx = layout.featureSlotIndices[key], layout.validateSingleBooleanSlot(slotIdx, in: data) { data[slotIdx * 8] = 1 }
                }
            }
            let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
            testDict["CacheData"] = data
            if case .success = layout.validatePlist(testDict) { self.mgCurrentDict["CacheData"] = data }
        } else if !isAppleIntellHD() {
            for key in MGKey.appIntellAllKeys { self.cacheExtra[key] = 1 }
        }
    }
    func isAdvAppleIntellStagedOrActive() -> Bool { return isAdvAppleIntellConflictActive() }
    func cacheResolutionFailureReason() -> String? {
        switch MGCacheDataCoordinator.shared.resolveValidated(for: mgCurrentDict) { case .success: return nil; case .failure(let err): return err.localizedDescription }
    }
    func mgChinaRestrictionCacheBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) else { return false }
                return data[layout.greenTeaOffset] == 0 && data[layout.notGreenTeaOffset] == 1
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    if enabled { data[layout.greenTeaOffset] = 0; data[layout.notGreenTeaOffset] = 1 }
                    else {
                        if let orig = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig), !(orig.greenTea == false && orig.notGreenTea == true) {
                            data[layout.greenTeaOffset] = orig.greenTea ? 1 : 0
                            data[layout.notGreenTeaOffset] = orig.notGreenTea ? 1 : 0
                        } else { data[layout.greenTeaOffset] = 1; data[layout.notGreenTeaOffset] = 0 }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success: self.objectWillChange.send(); self.mgCurrentDict["CacheData"] = data
                    }
                }
            }
        )
    }
    func mgWapiWifiBinding() -> Binding<Bool> {
        return Binding<Bool>(
            get: {
                guard case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict, checkWapiSlot: true), let wOff = layout.wapiOffset else { return false }
                return data[wOff] == 0
            },
            set: { enabled in
                switch MGCacheDataCoordinator.shared.resolveValidated(for: self.mgCurrentDict, checkWapiSlot: true) {
                case .failure(let err): Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: err.localizedDescription)
                case .success((let layout, var data)):
                    guard let wOff = layout.wapiOffset else { Alertinator.shared.alert(title: L("动态解析失败，已拒绝修改！"), body: L("当前系统库未能唯一解析 wapi 槽位偏移。")); return }
                    let savedOrig = NSDictionary(contentsOf: MGURL.savedGestaltURL)
                    if enabled { data[wOff] = 0 } else {
                        if let orig = MGCacheDataCoordinator.shared.originalFlags(for: layout, savedOriginalDict: savedOrig), let origWapi = orig.wapi, origWapi == true { data[wOff] = 1 } else { data[wOff] = 1 }
                    }
                    let testDict = NSMutableDictionary(dictionary: self.mgCurrentDict)
                    testDict["CacheData"] = data
                    switch layout.validatePlist(testDict, checkWapiSlot: true) {
                    case .failure(let err): Alertinator.shared.alert(title: L("缓存数据校验未通过，已拒绝修改！"), body: err.localizedDescription)
                    case .success:
                        self.objectWillChange.send(); self.mgCurrentDict["CacheData"] = data
                        if enabled { Alertinator.shared.alert(title: L("无线局域网改 Wi-Fi 重要提示"), body: MGMsg.wapiToWifi) }
                    }
                }
            }
        )
    }
}

// MARK: - EnsWilde Compat
extension GestaltStore {
    static func loadMutableDict(from url: URL) -> NSMutableDictionary? {
        guard let data = try? Data(contentsOf: url), let d = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else { return nil }
        return d
    }
    func loadFromPlist(url: URL) { if let d = Self.loadMutableDict(from: url) { mgCurrentDict = d; objectWillChange.send() } }
    func mgByteBinding(key: String, enableValue: UInt8 = 1, disableValue: UInt8 = 0) -> Binding<Bool> { return mgKeyBinding([key]) }
    func applyDynamicIsland(type: Int, customValue: Int? = nil) -> Bool {
        let subtypes = [0, 2436, 2556, 2796, 2976, 2622, 2868, 2736, 2662]
        guard let ce = mgCurrentDict["CacheExtra"] as? NSMutableDictionary else { return false }
        if type == 0 { (ce[MGKey.artwork] as? NSMutableDictionary)?.removeObject(forKey: "ArtworkDeviceSubType") }
        else if type > 0 && type < subtypes.count {
            let art = (ce[MGKey.artwork] as? NSMutableDictionary) ?? NSMutableDictionary()
            art["ArtworkDeviceSubType"] = subtypes[type]
            ce[MGKey.artwork] = art
        }
        objectWillChange.send()
        return true
    }
}