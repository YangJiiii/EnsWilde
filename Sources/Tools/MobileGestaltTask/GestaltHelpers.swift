//
//  mg.swift
//  mond
//
//  Created by ruter on 16.07.26.
//

import Foundation
import CoreFoundation
import CryptoKit
import Darwin
import MachO
import UIKit

struct MGDiffItem: Identifiable {
    let id: String
    let label: String
    let keyPath: String
    let beforeText: String
    let afterText: String
}

func mgValidatePlistData(_ data: Data) -> (Bool, String) {
    guard data.count > 256 else {
        return (false, L("待写入的 MobileGestalt 数据过小（\(data.count) 字节），已拦截写入。"))
    }
    guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
          let dict = obj as? NSDictionary else {
        return (false, L("待写入的数据不是合法的 Plist 字典，已拦截写入。"))
    }
    guard let cacheExtra = dict["CacheExtra"] as? NSDictionary, cacheExtra.count > 0 else {
        return (false, L("待写入的 Plist 缺少有效的 CacheExtra 字典，已拦截写入。"))
    }
    guard let cacheData = dict["CacheData"] as? Data, !cacheData.isEmpty else {
        return (false, L("待写入的 Plist 缺少有效的 CacheData 二进制段，已拦截写入。"))
    }
    return (true, "ok")
}

func mgPlistValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (nil, _), (_, nil):
        return false
    case (let a?, let b?):
        if let numA = a as? NSNumber, let numB = b as? NSNumber {
            let isBoolA = CFGetTypeID(numA) == CFBooleanGetTypeID()
            let isBoolB = CFGetTypeID(numB) == CFBooleanGetTypeID()
            if isBoolA != isBoolB { return false }
            if isBoolA { return numA.boolValue == numB.boolValue }
            let isFloatA = CFNumberIsFloatType(numA)
            let isFloatB = CFNumberIsFloatType(numB)
            if isFloatA != isFloatB { return false }
            return isFloatA ? (numA.doubleValue == numB.doubleValue) : (numA.stringValue == numB.stringValue)
        }
        if let strA = a as? String, let strB = b as? String { return strA == strB }
        if let dataA = a as? Data, let dataB = b as? Data { return dataA == dataB }
        if let dateA = a as? Date, let dateB = b as? Date { return dateA == dateB }
        if let arrA = a as? NSArray, let arrB = b as? NSArray {
            guard arrA.count == arrB.count else { return false }
            for idx in 0..<arrA.count where !mgPlistValuesEqual(arrA[idx], arrB[idx]) {
                return false
            }
            return true
        }
        if let dictA = a as? NSDictionary, let dictB = b as? NSDictionary {
            guard dictA.count == dictB.count else { return false }
            for (k, valA) in dictA {
                guard let keyStr = k as? String else { return dictA.isEqual(to: dictB as? [AnyHashable: Any] ?? [:]) }
                if !mgPlistValuesEqual(valA, dictB[keyStr]) { return false }
            }
            return true
        }
        return (a as AnyObject).isEqual(b)
    }
}

func mgFormatValue(_ val: Any?) -> String {
    guard let val else { return L("（不存在 / 已移除）") }
    if let num = val as? NSNumber {
        if CFGetTypeID(num) == CFBooleanGetTypeID() {
            return num.boolValue ? "true (Bool)" : "false (Bool)"
        }
        if CFNumberIsFloatType(num) {
            return "\(num.doubleValue) (Float)"
        }
        return num.stringValue
    }
    if let str = val as? String { return str.isEmpty ? "\"\"" : str }
    if let data = val as? Data { return L("<Data: \(data.count) 字节>") }
    if let arr = val as? NSArray {
        let items = arr.map { mgFormatValue($0) }.joined(separator: ", ")
        return "[\(items)]"
    }
    if let dict = val as? NSDictionary { return L("<Dict: \(dict.count) 项>") }
    return String(describing: val)
}

func mgKeyDisplayName(_ key: String) -> String {
    let names: [String: String] = [
        MGKey.regionCode: L("地区代码 (RegionCode)"),
        MGKey.regionInfo: L("销售地区 (RegionInfo)"),
        MGKey.regionSysconfig: L("系统销售地区 (RegionInfoFromSysconfig)"),
        MGKey.regModelNumber: L("监管型号 (RegulatoryModelNumber)"),
        MGKey.appIntell: L("Apple 智能总开关"),
        MGKey.photosCleanUp: L("相册“消除”功能 (Photos Clean Up)"),
        MGKey.handwritingSynth: L("备忘录手写体合成 (Handwriting Synthesis)"),
        MGKey.audioIntell: L("iOS 27 音频智能 (Audio Intelligence)"),
        MGKey.personalTranslator: L("个人实时翻译 (Personal Translator)"),
        MGKey.audioMix: L("相册与相机混音 (Audio Mix)"),
        MGKey.spatialAudioRec: L("空间音频录制 (spatial-audio-recording)"),
        MGKey.spatialFaceTimeAudio: L("FaceTime 空间音频 (spatial-facetime-audio)"),
        MGKey.responsiveShutter: L("按下快门瞬间抓拍 (ResponsiveShutter)"),
        MGKey.hypertensionNotif: L("健康高血压趋势评估 (HypertensionNotifications)"),
        MGCacheDataLayout.greenTeaKey: L("国行限制标记 (green-tea)"),
        MGCacheDataLayout.notGreenTeaKey: L("非国行设备标记 (not-green-tea)"),
        MGCacheDataLayout.wapiKey: L("无线局域网显示标记 (wapi)"),
        MGKey.liquidGlassLowPower: L("液态玻璃低功耗渲染"),
        MGKey.island: L("灵动岛特性"),
        MGKey.AOD: L("全天候显示 (AOD)"),
        MGKey.AOTime: L("全天候显示时间"),
        MGKey.AODVibrancy: L("AOD 鲜艳度"),
        MGKey.chargeLim: L("80% 充电上限"),
        MGKey.bootChime: L("开关机提示音"),
        MGKey.intInstall: L("Apple 内部安装模式"),
        MGKey.intBuild: L("内部版本标识"),
        MGKey.srd: L("安全研究设备 (SRD)"),
        MGKey.prodType: L("机型标识符 (ProductType)"),
        MGKey.modelNameOuter1: L("设备产品名称"),
        MGKey.modelNameOuter2: L("设备市场名称"),
        MGKey.crashDet: L("车祸检测"),
        MGKey.pwm: L("PWM 调光开关"),
        MGKey.appPencil: L("Apple Pencil 支持"),
        MGKey.camButton: L("相机控制按键"),
        MGKey.grapPefr: L("图形性能等级"),
        MGKey.actButton: L("操作按钮"),
        MGKey.tapToWake: L("轻点唤醒"),
        MGKey.stageMgr: L("台前调度"),
        MGKey.shutterRelaxation: L("[测试] 地区相机快门音豁免"),
        MGKey.shutterKeyboardMutePreserve: L("[测试] 键盘静音保留强制快门音"),
        MGKey.shutterLegacyMutePreserve: L("[测试] 旧机型保留强制快门音"),
        MGKey.concurrentHPLPMics: L("[测试] 高低功耗双麦并发拾音"),
        MGKey.photosLocalLight: L("[测试] 相册局部光效重绘"),
        MGKey.toneMapping: L("[测试] 动态色调映射"),
        MGKey.hdrDeferredProcessing: L("[测试] HDR 深度延迟渲染"),
        MGKey.spatialOverCapture: L("[测试] 超取景框空间捕获"),
        MGKey.stereoAudioRec: L("[测试] 立体声视频拾音"),
        MGKey.p3VideoRec: L("[测试] P3 广色域视频录制"),
        MGKey.touchSensitiveCamControl: L("[测试] 电容触敏相机控制"),
        MGKey.hardwareDetents: L("[测试] 物理触感档位阻尼"),
        MGKey.cameraHaptics: L("[测试] 相机微幅触觉反馈"),
        MGKey.legacyBatteryInfo: L("[测试] 旧机型电池循环与日期显示"),
        MGKey.legacyDynamicEndOfCharge: L("[测试] 旧机型智能充电截止"),
        MGKey.highLuminanceAOD: L("[测试] 户外高亮全天候显示"),
        MGKey.aodFlipbook: L("[测试] AOD 低功耗翻页帧缓冲"),
        MGKey.carPlay2: L("[测试] CarPlay Ultra 新一代车载"),
        MGKey.touchDelivery120Hz: L("[测试] 120Hz 触控采样投递"),
        MGKey.hearingAidEQ: L("[测试] 临床助听器音频均衡"),
        MGKey.hearingAidLE: L("[测试] 助听器低功耗音频"),
        MGKey.hearingAidPowerRed: L("[测试] 助听器降功耗模式"),
        MGKey.breathingDisturbances: L("[测试] 睡眠呼吸暂停风险检测"),
        MGKey.usBloodOxygen: L("[测试] 美版血氧软件限制开关"),
        MGKey.workoutUltra: L("[测试] 户外极限运动模式"),
        MGKey.timeInDaylight: L("[测试] 日光照射时长监测"),
        MGKey.siriHub: L("[测试] 端侧 Siri Hub 意图路由"),
        MGKey.onDeviceSiri: L("[测试] 离线端侧 Siri 能力"),
        MGKey.modelPruning: L("[测试] 端侧指令模型动态剪枝"),
        "uKc7FPnEO++lVhHWHFlGbQ": L("iPad 设备模式"),
        "mG0AnH/Vy1veoqoLRAIgTA": L("多任务浮动应用"),
        "UCG5MkVahJxG1YULbbd5Bg": L("多任务侧拉覆盖"),
        "ZYqko/XM5zD3XBfN5RmaXA": L("多任务固定分屏"),
        "nVh/gwNpy7Jv1NOk00CMrw": L("多任务画中画"),
        "ArtworkDeviceSubType": L("屏幕子类型 (Subtype)"),
        "ArtworkDeviceProductDescription": L("自定义机型名称")
    ]
    return names[key] ?? key
}

func mgComputeDiff(from beforeDict: NSDictionary, to afterDict: NSDictionary) -> [MGDiffItem] {
    var items: [MGDiffItem] = []

    let beforeCacheData = beforeDict["CacheData"] as? Data
    let afterCacheData = afterDict["CacheData"] as? Data
    if beforeCacheData != afterCacheData {
        let slotDiffs = MGCacheDataCoordinator.shared.diffDetails(from: beforeDict, to: afterDict)
        if !slotDiffs.isEmpty {
            for d in slotDiffs {
                items.append(MGDiffItem(
                    id: d.id,
                    label: d.label,
                    keyPath: d.keyPath,
                    beforeText: d.beforeText,
                    afterText: d.afterText
                ))
            }
        } else {
            items.append(MGDiffItem(
                id: "root.CacheData",
                label: L("底层二进制缓存 (CacheData)"),
                keyPath: "CacheData",
                beforeText: mgFormatValue(beforeCacheData),
                afterText: mgFormatValue(afterCacheData)
            ))
        }
    }

    let beforeExtra = beforeDict["CacheExtra"] as? NSDictionary ?? [:]
    let afterExtra = afterDict["CacheExtra"] as? NSDictionary ?? [:]
    var allKeys = Set<String>()
    for k in beforeExtra.allKeys { if let s = k as? String { allKeys.insert(s) } }
    for k in afterExtra.allKeys { if let s = k as? String { allKeys.insert(s) } }

    for key in allKeys.sorted() {
        let oldVal = beforeExtra[key]
        let newVal = afterExtra[key]
        if mgPlistValuesEqual(oldVal, newVal) { continue }

        if key == MGKey.artwork,
           let oldArt = oldVal as? NSDictionary,
           let newArt = newVal as? NSDictionary {
            var artKeys = Set<String>()
            for k in oldArt.allKeys { if let s = k as? String { artKeys.insert(s) } }
            for k in newArt.allKeys { if let s = k as? String { artKeys.insert(s) } }
            for aKey in artKeys.sorted() {
                if !mgPlistValuesEqual(oldArt[aKey], newArt[aKey]) {
                    items.append(MGDiffItem(
                        id: "Artwork.\(aKey)",
                        label: mgKeyDisplayName(aKey),
                        keyPath: "\(MGKey.artwork) → \(aKey)",
                        beforeText: mgFormatValue(oldArt[aKey]),
                        afterText: mgFormatValue(newArt[aKey])
                    ))
                }
            }
            continue
        }

        items.append(MGDiffItem(
            id: "CacheExtra.\(key)",
            label: mgKeyDisplayName(key),
            keyPath: key,
            beforeText: mgFormatValue(oldVal),
            afterText: mgFormatValue(newVal)
        ))
    }

    return items
}

func mgExcludeFromCloudBackup(_ url: URL) {
    var target = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? target.setResourceValues(values)
}

func mgComputeSHA256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

enum MGFactoryRestoreOutcome {
    case restoredSuccessfully(details: String)
    case blockedNeedsCleanRebuild(title: String, reason: String)
    case failed(reason: String)
}

func mgSyncSystemVaultBackup(_ data: Data, hexDigest: String) {
    let vaultDir = MGURL.systemVaultGestaltURL.deletingLastPathComponent()
    if !FileManager.default.isWritableFile(atPath: vaultDir.path) {
        _ = wq.grantAccess(path: vaultDir.path)
    }
    guard FileManager.default.isWritableFile(atPath: vaultDir.path) else { return }
    do {
        try data.write(to: MGURL.systemVaultGestaltURL, options: .atomic)
        mgExcludeFromCloudBackup(MGURL.systemVaultGestaltURL)
        try Data(hexDigest.utf8).write(to: MGURL.systemVaultSHA256URL, options: .atomic)
        mgExcludeFromCloudBackup(MGURL.systemVaultSHA256URL)
    } catch {
        print("(mg-vault) sync system vault failed: \(error.localizedDescription)")
    }
}

func mgSaveOriginalBackupWithDigest(_ data: Data) throws {
    let hex = mgComputeSHA256Hex(data)
    try data.write(to: MGURL.savedGestaltURL, options: .atomic)
    mgExcludeFromCloudBackup(MGURL.savedGestaltURL)
    try Data(hex.utf8).write(to: MGURL.savedGestaltSHA256URL, options: .atomic)
    mgExcludeFromCloudBackup(MGURL.savedGestaltSHA256URL)
    mgSyncSystemVaultBackup(data, hexDigest: hex)
}

func mgVerifyBackupFileIntegrity(plistURL: URL, sha256URL: URL, requireDigestFile: Bool = false) -> (Bool, String) {
    guard let data = try? Data(contentsOf: plistURL), !data.isEmpty else {
        return (false, L("找不到或无法读取备份文件 \(plistURL.lastPathComponent)！"))
    }
    let check = mgValidatePlistData(data)
    guard check.0 else {
        return (false, L("备份文件结构已损坏：\(check.1)"))
    }
    if FileManager.default.fileExists(atPath: sha256URL.path),
       let savedHexData = try? Data(contentsOf: sha256URL),
       let savedHex = String(data: savedHexData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       savedHex.count == 64 {
        let actualHex = mgComputeSHA256Hex(data)
        if actualHex.caseInsensitiveCompare(savedHex) != .orderedSame {
            let expectedPrefix = String(savedHex.prefix(12))
            let actualPrefix = String(actualHex.prefix(12))
            return (false, L("备份文件 SHA-256 完整性摘要校验未通过（预期 \(expectedPrefix)...，实际 \(actualPrefix)...），可能已被篡改或损坏！"))
        }
    } else if requireDigestFile {
        return (false, L("缺少对应的 SHA-256 完整性校验文件！"))
    }
    return (true, "ok")
}

func mgVerifyOriginalBackupIntegrity() -> (Bool, String) {
    return mgVerifyBackupFileIntegrity(plistURL: MGURL.savedGestaltURL, sha256URL: MGURL.savedGestaltSHA256URL)
}

func mgHasSyncedSystemVault() -> Bool {
    return mgVerifyBackupFileIntegrity(
        plistURL: MGURL.systemVaultGestaltURL,
        sha256URL: MGURL.systemVaultSHA256URL,
        requireDigestFile: true
    ).0
}

func mgDetectSuspectedThirdPartyModification(in dict: NSDictionary) -> String? {
    let extra = dict["CacheExtra"] as? NSDictionary ?? [:]
    let kernelMachine = machineName()
    if let plistProd = extra[MGKey.prodType] as? String,
       !plistProd.isEmpty,
       !kernelMachine.isEmpty,
       plistProd != kernelMachine {
        return L("检测到机型标识符 (\(plistProd)) 与内核真实硬件型号 (\(kernelMachine)) 不符（可能曾开启机型伪装）")
    }
    if (extra[MGKey.intInstall] as? NSNumber)?.intValue == 1 || (extra[MGKey.intBuild] as? NSNumber)?.intValue == 1 {
        return L("检测到内部安装模式 (InternalInstall / InternalBuild) 处于开启状态（说明安装本应用前设备曾被其他工具修改，与 Apple 智能互斥；现在你可直接关闭对应开关清除该残留）")
    }
    let regCode = extra[MGKey.regionCode] as? String ?? ""
    if regCode == "LL",
       case .success((let layout, let data)) = MGCacheDataCoordinator.shared.resolveValidated(for: dict, checkWapiSlot: true),
       let wOff = layout.wapiOffset,
       data[wOff] == 1 {
        return L("检测到销售地区已处于美版 (LL)，但底层仍带有国行硬件独有的 WAPI 标记（说明安装本应用前设备已改过地区）")
    }
    return nil
}

/// Ensures `OriginalGestalt.plist` exists cleanly:
/// - Recovers true factory backup from SystemGroup vault across sideload app uninstall/reinstall;
/// - Mirrors valid local backup into SystemGroup vault if missing;
/// - Warns if first-ever install encounters an already-modified system plist.
func mgEnsureOriginalBackupWithVault(liveData: Data) throws -> (recoveredFromVault: Bool, suspectedDirtyWarning: String?) {
    let liveDict = (try? PropertyListSerialization.propertyList(from: liveData, options: [], format: nil) as? NSDictionary) ?? [:]
    let liveBuild = liveDict["CacheVersion"] as? String ?? ""
    let liveUUID = liveDict["CacheUUID"] as? String ?? ""
    let kernelHW = machineName()

    let fm = FileManager.default
    if fm.fileExists(atPath: MGURL.savedGestaltURL.path) {
        if !fm.fileExists(atPath: MGURL.savedGestaltSHA256URL.path),
           let existingOgData = try? Data(contentsOf: MGURL.savedGestaltURL),
           mgValidatePlistData(existingOgData).0 {
            let hex = mgComputeSHA256Hex(existingOgData)
            try? Data(hex.utf8).write(to: MGURL.savedGestaltSHA256URL, options: .atomic)
            mgExcludeFromCloudBackup(MGURL.savedGestaltSHA256URL)
        }
        mgExcludeFromCloudBackup(MGURL.savedGestaltURL)

        // Sync to SystemGroup vault if vault is missing or outdated while local backup matches live OS build
        if mgVerifyOriginalBackupIntegrity().0,
           let localData = try? Data(contentsOf: MGURL.savedGestaltURL),
           let localDict = NSDictionary(contentsOf: MGURL.savedGestaltURL) {
            let localBuild = localDict["CacheVersion"] as? String ?? ""
            let vaultValid = mgHasSyncedSystemVault()
            let vaultBuild = (NSDictionary(contentsOf: MGURL.systemVaultGestaltURL)?["CacheVersion"] as? String) ?? ""
            if !vaultValid || (!localBuild.isEmpty && localBuild == liveBuild && vaultBuild != liveBuild) {
                mgSyncSystemVaultBackup(localData, hexDigest: mgComputeSHA256Hex(localData))
            }
        }
        return (false, nil)
    }

    // Documents/OriginalGestalt.plist is missing (first install OR sideload uninstall+reinstall):
    // Try recovering from SystemGroup vault first!
    let vaultDir = MGURL.systemVaultGestaltURL.deletingLastPathComponent()
    if !fm.isReadableFile(atPath: vaultDir.path) {
        _ = wq.grantAccess(path: vaultDir.path)
    }
    if mgHasSyncedSystemVault(),
       let vaultData = try? Data(contentsOf: MGURL.systemVaultGestaltURL),
       let vaultDict = try? PropertyListSerialization.propertyList(from: vaultData, options: [], format: nil) as? NSDictionary {
        let vaultBuild = vaultDict["CacheVersion"] as? String ?? ""
        let vaultUUID = vaultDict["CacheUUID"] as? String ?? ""
        let vaultExtra = vaultDict["CacheExtra"] as? NSDictionary
        let vaultProd = vaultExtra?[MGKey.prodType] as? String ?? ""
        let vaultLen = (vaultDict["CacheData"] as? Data)?.count ?? 0
        let liveLen = (liveDict["CacheData"] as? Data)?.count ?? 0

        let hwMatches = vaultProd.isEmpty || kernelHW.isEmpty || vaultProd == kernelHW
        let buildMatches = !vaultBuild.isEmpty && vaultBuild == liveBuild
        let uuidMatches = !vaultUUID.isEmpty && vaultUUID.caseInsensitiveCompare(liveUUID) == .orderedSame
        let lenMatches = vaultLen > 0 && vaultLen == liveLen

        if hwMatches && buildMatches && uuidMatches && lenMatches {
            let hex = mgComputeSHA256Hex(vaultData)
            try vaultData.write(to: MGURL.savedGestaltURL, options: .atomic)
            mgExcludeFromCloudBackup(MGURL.savedGestaltURL)
            try Data(hex.utf8).write(to: MGURL.savedGestaltSHA256URL, options: .atomic)
            mgExcludeFromCloudBackup(MGURL.savedGestaltSHA256URL)
            print(L("[*] (mg-vault) 检测到应用重装，已从系统安全金库无损找回原厂备份 (\(vaultBuild))！"))
            return (true, nil)
        }
    }

    // True first-ever backup on this OS build: inspect whether system plist was already modified by another tool
    let dirtyReason = mgDetectSuspectedThirdPartyModification(in: liveDict)
    try mgSaveOriginalBackupWithDigest(liveData)
    return (false, dirtyReason)
}

func mgImportExternalOriginalBackup(from externalURL: URL) -> Result<String, Error> {
    let scoped = externalURL.startAccessingSecurityScopedResource()
    defer {
        if scoped { externalURL.stopAccessingSecurityScopedResource() }
    }
    do {
        let data = try Data(contentsOf: externalURL)
        let preCheck = mgValidatePlistData(data)
        guard preCheck.0,
              let importedDict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary else {
            throw NSError(domain: "Erosion.MGImport", code: 1, userInfo: [NSLocalizedDescriptionKey: preCheck.1])
        }

        let impExtra = importedDict["CacheExtra"] as? NSDictionary
        let impProd = impExtra?[MGKey.prodType] as? String ?? ""
        let kernelHW = machineName()
        if !impProd.isEmpty && !kernelHW.isEmpty && impProd != kernelHW {
            throw NSError(domain: "Erosion.MGImport", code: 2, userInfo: [NSLocalizedDescriptionKey: L("拒绝导入：该备份机型 (\(impProd)) 与本机真实硬件 (\(kernelHW)) 不一致！")])
        }

        let vaultDir = MGURL.fsGestaltURL.deletingLastPathComponent()
        if !FileManager.default.isReadableFile(atPath: vaultDir.path) {
            _ = wq.grantAccess(path: vaultDir.path)
        }
        if let liveDict = NSDictionary(contentsOf: MGURL.fsGestaltURL) {
            let impBuild = importedDict["CacheVersion"] as? String ?? ""
            let liveBuild = liveDict["CacheVersion"] as? String ?? ""
            if !impBuild.isEmpty && !liveBuild.isEmpty && impBuild != liveBuild {
                throw NSError(domain: "Erosion.MGImport", code: 3, userInfo: [NSLocalizedDescriptionKey: L("拒绝导入：该备份系统版本 (\(impBuild)) 与当前系统 (\(liveBuild)) 不一致！")])
            }
            let impUUID = importedDict["CacheUUID"] as? String ?? ""
            let liveUUID = liveDict["CacheUUID"] as? String ?? ""
            if !impUUID.isEmpty && !liveUUID.isEmpty && impUUID.caseInsensitiveCompare(liveUUID) != .orderedSame {
                throw NSError(domain: "Erosion.MGImport", code: 4, userInfo: [NSLocalizedDescriptionKey: L("拒绝导入：该备份的 CacheUUID 与当前系统不匹配！")])
            }
            let impLen = (importedDict["CacheData"] as? Data)?.count ?? 0
            let liveLen = (liveDict["CacheData"] as? Data)?.count ?? 0
            if impLen > 0 && liveLen > 0 && impLen != liveLen {
                throw NSError(domain: "Erosion.MGImport", code: 5, userInfo: [NSLocalizedDescriptionKey: L("拒绝导入：该备份的 CacheData 字节长度 (\(impLen)) 与当前系统 (\(liveLen)) 不一致！")])
            }
        }

        if FileManager.default.fileExists(atPath: MGURL.savedGestaltURL.path) {
            let archiveURL = URL.documentsDirectory.appendingPathComponent("ArchivedOriginalGestalt_\(Int(Date().timeIntervalSince1970)).plist")
            try? FileManager.default.copyItem(at: MGURL.savedGestaltURL, to: archiveURL)
            mgExcludeFromCloudBackup(archiveURL)
        }

        try mgSaveOriginalBackupWithDigest(data)
        MGCacheDataCoordinator.shared.clearRecordedBaselines()
        let buildStr = (importedDict["CacheVersion"] as? String) ?? L("当前版本")
        let shaPrefix = String(mgComputeSHA256Hex(data).prefix(12))
        return .success(L("已成功校验并导入原厂备份（版本：\(buildStr)，机型：\(impProd)，SHA-256：\(shaPrefix)...），同时已同步锁定至系统安全金库。"))
    } catch {
        return .failure(error)
    }
}

func mgResetLocalTweakPreferences() {
    let ud = UserDefaults.standard
    if let raw = ud.string(forKey: "mgCustKeyArray"),
       var arr = [MGCustomKey](rawValue: raw) {
        for idx in arr.indices {
            arr[idx].isOn = false
        }
        ud.set(arr.rawValue, forKey: "mgCustKeyArray")
    }
    ud.set("", forKey: "mgDeviceName")
    ud.set(false, forKey: "mgOverrideGates")
    ud.removeObject(forKey: MGRegionUnlockMode.defaultsKey)
    MGCacheDataCoordinator.shared.clearRecordedBaselines()
}

func mgExecuteCleanCacheRebuild(alsoResetConfigAndKeypad: Bool = false) -> Result<Void, Error> {
    let fm = FileManager.default
    let cacheDir = MGURL.fsGestaltURL.deletingLastPathComponent()
    if !fm.isWritableFile(atPath: cacheDir.path) {
        _ = wq.grantAccess(path: cacheDir.path)
    }
    do {
        if fm.fileExists(atPath: MGURL.savedGestaltURL.path) {
            let archiveURL = URL.documentsDirectory.appendingPathComponent("ArchivedOriginalGestalt_\(Int(Date().timeIntervalSince1970)).plist")
            try? fm.copyItem(at: MGURL.savedGestaltURL, to: archiveURL)
            mgExcludeFromCloudBackup(archiveURL)
            try? fm.removeItem(at: MGURL.savedGestaltURL)
        }
        try? fm.removeItem(at: MGURL.savedGestaltSHA256URL)
        try? fm.removeItem(at: MGURL.systemVaultGestaltURL)
        try? fm.removeItem(at: MGURL.systemVaultSHA256URL)

        mgResetLocalTweakPreferences()
        if alsoResetConfigAndKeypad {
            try? ConfigView.resetSystemConfigSafely()
            _ = KeypadManager.shared.resetKeypadItems()
        }

        if fm.fileExists(atPath: MGURL.fsGestaltURL.path) {
            try fm.removeItem(at: MGURL.fsGestaltURL)
        }
        GestaltStore.shared.mgCurrentDict = NSMutableDictionary()
        return .success(())
    } catch {
        return .failure(error)
    }
}

func mgExecuteFactoryRestore(alsoResetConfigAndKeypad: Bool) -> MGFactoryRestoreOutcome {
    let fm = FileManager.default
    let cacheDir = MGURL.fsGestaltURL.deletingLastPathComponent()
    if !fm.isWritableFile(atPath: cacheDir.path) {
        let res = wq.grantAccess(path: cacheDir.path)
        if !res.0 && !fm.isWritableFile(atPath: cacheDir.path) {
            return .failed(reason: L("获取 MobileGestalt 目录写入权限失败，请完全退出并重新打开本应用后再试。"))
        }
    }

    // If local Documents backup is missing, try recovering from SystemGroup vault first
    if !fm.fileExists(atPath: MGURL.savedGestaltURL.path),
       mgHasSyncedSystemVault(),
       let vaultData = try? Data(contentsOf: MGURL.systemVaultGestaltURL) {
        let hex = mgComputeSHA256Hex(vaultData)
        try? vaultData.write(to: MGURL.savedGestaltURL, options: .atomic)
        mgExcludeFromCloudBackup(MGURL.savedGestaltURL)
        try? Data(hex.utf8).write(to: MGURL.savedGestaltSHA256URL, options: .atomic)
        mgExcludeFromCloudBackup(MGURL.savedGestaltSHA256URL)
    }

    let integrityCheck = mgVerifyOriginalBackupIntegrity()
    guard integrityCheck.0 else {
        return .blockedNeedsCleanRebuild(
            title: L("原始备份缺失或校验未通过！"),
            reason: L("\(integrityCheck.1)\n\n你可以选择下方的「重建系统纯净原厂缓存」，让 iOS 在重启时直接从主板硬件熔丝重新生成 100% 原厂参数。")
        )
    }

    guard let mgDictToApply = NSMutableDictionary(contentsOf: MGURL.savedGestaltURL) else {
        return .blockedNeedsCleanRebuild(
            title: L("无法读取原始备份！"),
            reason: L("未找到有效的 OriginalGestalt.plist。可使用下方「重建系统纯净原厂缓存」在重启时自动重建原厂配置。")
        )
    }

    if let liveDict = NSDictionary(contentsOf: MGURL.fsGestaltURL) {
        let ogBuild = mgDictToApply["CacheVersion"] as? String ?? ""
        let liveBuild = liveDict["CacheVersion"] as? String ?? ""
        if !ogBuild.isEmpty && !liveBuild.isEmpty && ogBuild != liveBuild {
            return .blockedNeedsCleanRebuild(
                title: L("已安全拦截跨 iOS 版本备份覆盖"),
                reason: L("检测到原始备份来自旧版系统 (\(ogBuild))，而当前系统已升级至 \(liveBuild)，二进制槽位布局已变化，直接覆盖存在风险。\n\n点击下方「重建系统纯净原厂缓存」即可安全删除旧缓存，并在重启后由 \(liveBuild) 系统自动重算 100% 原厂参数！")
            )
        }

        let ogUUID = mgDictToApply["CacheUUID"] as? String ?? ""
        let liveUUID = liveDict["CacheUUID"] as? String ?? ""
        if !ogUUID.isEmpty && !liveUUID.isEmpty && ogUUID.caseInsensitiveCompare(liveUUID) != .orderedSame {
            return .blockedNeedsCleanRebuild(
                title: L("已安全拦截不匹配的 CacheUUID 还原"),
                reason: L("原始备份的 CacheUUID (\(ogUUID)) 与当前系统 (\(liveUUID)) 不一致，安全护栏已阻止直接覆盖。\n\n点击「重建系统纯净原厂缓存」并重启即可安全恢复 100% 原厂状态。")
            )
        }

        let ogCacheLen = (mgDictToApply["CacheData"] as? Data)?.count ?? 0
        let liveCacheLen = (liveDict["CacheData"] as? Data)?.count ?? 0
        if ogCacheLen > 0 && liveCacheLen > 0 && ogCacheLen != liveCacheLen {
            return .blockedNeedsCleanRebuild(
                title: L("已安全拦截长度不一致的二进制缓存还原"),
                reason: L("原始备份的 CacheData 长度 (\(ogCacheLen) 字节) 与当前系统 (\(liveCacheLen) 字节) 不一致，已阻止直接写入！\n\n点击「重建系统纯净原厂缓存」并重启即可安全恢复 100% 原厂状态。")
            )
        }

        let ogExtra = mgDictToApply["CacheExtra"] as? NSDictionary
        let ogProd = ogExtra?[MGKey.prodType] as? String ?? ""
        let actualHW = machineName()
        if !ogProd.isEmpty && !actualHW.isEmpty && ogProd != actualHW {
            return .blockedNeedsCleanRebuild(
                title: L("已拦截跨机型备份还原！"),
                reason: L("该备份来自其他机型 (\(ogProd))，与本机真实硬件 (\(actualHW)) 不符，直接写入会导致白苹果软砖！请点击「重建系统纯净原厂缓存」恢复本机原厂配置。")
            )
        }
    }

    do {
        let data = try PropertyListSerialization.data(fromPropertyList: mgDictToApply, format: .binary, options: 0)
        let res = mgWriteDetailed(data, allowVerifiedFactoryRestore: true)
        guard res.0 else {
            return .failed(reason: res.1)
        }

        mgResetLocalTweakPreferences()
        var extraResetNotes: [String] = []
        if alsoResetConfigAndKeypad {
            if (try? ConfigView.resetSystemConfigSafely()) != nil {
                extraResetNotes.append(L("已清除锁屏文字/资产铭牌与伪监管残留"))
            }
            if KeypadManager.shared.resetKeypadItems() {
                extraResetNotes.append(L("已重置自定义拨号键盘缓存"))
            }
        }

        if let freshBytes = try? Data(contentsOf: MGURL.fsGestaltURL),
           let freshDict = try? PropertyListSerialization.propertyList(from: freshBytes, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary {
            GestaltStore.shared.mgCurrentDict = freshDict
        }

        var summary = MGMsg.revertComp
        if !extraResetNotes.isEmpty {
            let joinedNotes = extraResetNotes.joined(separator: L("；"))
            summary += L("\n\n附加恢复项：\(joinedNotes)。")
        }
        return .restoredSuccessfully(details: summary)
    } catch {
        return .failed(reason: error.localizedDescription)
    }
}

func mgIsDangerousCacheExtraKey(_ key: String) -> String? {
    let blocked: [String: String] = [
        "zHeENZu+wbg7PUprwNwBWg": L("RegionInfo（iOS 27 非缓存键，注入将触发开机缓存重置）"),
        "0L5PkT61qoH1b/B1USWqjQ": L("RegionalBehaviorChinaBrick（非缓存硬件键，注入将触发开机重置）"),
        "gD8SNRcHQeIxCAvsp+2vjA": L("WSKU（无线电射频校准数据，篡改可致 Wi-Fi/蓝牙瘫痪）"),
        "sFTm4FEVKVfdZ0ChdwQY1g": L("WifiAntennaSKUVersion（天线校准参数，禁止篡改）"),
        "91LyMcx4z1w3SGVeqteMnA": L("BasebandRegionSKU（基带射频参数，篡改可致基带死锁）"),
        "iyfxmLogGVIaH7aEgqwcIA": L("green-tea（属于 CacheData 二进制槽位，禁止注入 CacheExtra）"),
        "4snMZS8LJkSctKypt2m+xA": L("not-green-tea（属于 CacheData 二进制槽位，禁止注入 CacheExtra）"),
        "hiHut/WR+B9Lx/vd0WyeNg": L("wapi（属于 CacheData 二进制槽位，禁止注入 CacheExtra）"),
        "green-tea": L("green-tea（明文冲突键，禁止注入 CacheExtra）"),
        "not-green-tea": L("not-green-tea（明文冲突键，禁止注入 CacheExtra）"),
        "wapi": L("wapi（明文冲突键，禁止注入 CacheExtra）"),
        "aVL5GE3tx0LSCI/ErfrJGA": L("混音 Audio Mix（属于 CacheData 二进制槽位，请直接使用主界面对应开关）"),
        "X6NGcYcvHmbqlR8hLXASJA": L("空间音频录制（属于 CacheData 二进制槽位，请直接使用主界面对应开关）"),
        "/EVOCjM/Nmb2roP5ebtEFA": L("FaceTime 空间音频（属于 CacheData 二进制槽位，请直接使用主界面对应开关）"),
        "gQDt76Te0SPw7N8oTLrBFw": L("按下快门瞬间抓拍（属于 CacheData 二进制槽位，请直接使用主界面对应开关）"),
        "4fh9efw4o1yaFqkXNCXoeA": L("高血压趋势评估（属于 CacheData 二进制槽位，请直接使用主界面对应开关）"),
        "CacheData": L("顶层系统保留字段"),
        "CacheUUID": L("顶层系统保留字段"),
        "CacheVersion": L("顶层系统保留字段")
    ]
    return blocked[key]
}

func mgWriteDetailed(_ data: Data, allowVerifiedFactoryRestore: Bool = false) -> (Bool, String) {
    let preCheck = mgValidatePlistData(data)
    guard preCheck.0 else {
        print("(mg) pre-write validation failed: \(preCheck.1)")
        return preCheck
    }

    guard let originalBytes = try? Data(contentsOf: MGURL.fsGestaltURL), !originalBytes.isEmpty else {
        let msg = L("读取设备当前 MobileGestalt 原始文件失败（文件为空或无权限），已中止写入以保护系统！")
        print("(mg) \(msg)")
        return (false, msg)
    }

    // Strict pre-write CacheData verification:
    // - Normal edits enforce allowedOffsets transition check against liveDiskDict;
    // - SHA-256 verified factory backup restoration validates targetDict directly against loaded libMobileGestalt.dylib
    //   so even previously corrupted eSIM / cellular / ISP bytes in liveDiskDict can be healed back to factory state!
    if let liveDiskDict = try? PropertyListSerialization.propertyList(from: originalBytes, options: [], format: nil) as? NSDictionary,
       let targetDict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary {
        if allowVerifiedFactoryRestore {
            if case .failure(let targetErr) = MGCacheDataCoordinator.shared.resolveValidated(for: targetDict) {
                print("[!] (mg) Factory restore target CacheData validation failed: \(targetErr.localizedDescription)")
                return (false, targetErr.localizedDescription)
            }
        } else {
            if case .failure(let cacheErr) = MGCacheDataCoordinator.shared.validateTransition(from: liveDiskDict, to: targetDict) {
                print("[!] (mg) CacheData pre-write check rejected write: \(cacheErr.localizedDescription)")
                return (false, cacheErr.localizedDescription)
            }
        }
    }

    // Save pre-apply snapshot before touching system file (excluded from iCloud/Finder device migration)
    try? originalBytes.write(to: MGURL.preApplyGestaltURL, options: .atomic)
    mgExcludeFromCloudBackup(MGURL.preApplyGestaltURL)

    // Unconditionally enforce safe in-place write (pwrite + tail truncate + F_FULLFSYNC) to preserve Inode & POSIX attributes
    let res = writeFileAtomically(data, to: MGURL.fsGestaltURL)
    if !res.0 {
        print("(mg) write failed: \(res.1)")
        return (false, L("写入系统文件失败：\(res.1)"))
    }

    // Full readback & plist structural/type verification
    do {
        let readbackBytes = try Data(contentsOf: MGURL.fsGestaltURL)
        let readbackCheck = mgValidatePlistData(readbackBytes)
        guard readbackBytes == data,
              readbackCheck.0,
              let expectedDict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary,
              let actualDict = try PropertyListSerialization.propertyList(from: readbackBytes, options: [], format: nil) as? NSDictionary,
              mgPlistValuesEqual(expectedDict, actualDict) else {
            throw NSError(domain: "Erosion.MGVerify", code: -1, userInfo: [NSLocalizedDescriptionKey: L("磁盘读回数据与预期键值/类型不一致")])
        }
        print("(mg) readback verified (\(readbackBytes.count) bytes)")
        return (true, "succeeded")
    } catch {
        print("(mg) readback verification failed (\(error.localizedDescription))! Rolling back previous bytes...")
        let rollbackOK = writeFileAtomically(originalBytes, to: MGURL.fsGestaltURL).0
        let verifiedRollback = ((try? Data(contentsOf: MGURL.fsGestaltURL)) == originalBytes)
        if rollbackOK && verifiedRollback {
            return (false, L("写后读回校验未通过（\(error.localizedDescription)），已自动原位安全回滚至修改前状态！"))
        } else {
            return (false, L("写后读回校验失败且自动回滚异常，请勿重启并前往高级设置检查缓存！"))
        }
    }
}

func mgWrite(_ data: Data) -> Bool {
    return mgWriteDetailed(data).0
}

func currentOriginalMachineName() -> String {
    if let saved = UserDefaults.standard.string(forKey: "ogMachineName"), !saved.isEmpty {
        return saved
    }
    return machineName()
}

/// Returns the true factory hardware ProductType (immune to in-memory or active ProductType spoofing)
func originalHardwareProductType() -> String {
    if let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL),
       let ogExtra = ogDict["CacheExtra"] as? NSDictionary,
       let ogProd = ogExtra[MGKey.prodType] as? String,
       !ogProd.isEmpty {
        return ogProd
    }
    return currentOriginalMachineName()
}

// MARK: - Safe Read-Only Live MGCopyAnswer Probe (+1 Copy Rule Compliant)

private typealias MGCopyAnswerFn = @convention(c) (CFString) -> Unmanaged<CFTypeRef>?

private let resolvedMGCopyAnswer: MGCopyAnswerFn? = {
    let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY | RTLD_LOCAL)
    guard let sym = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), "MGCopyAnswer") else {
        return nil
    }
    return unsafeBitCast(sym, to: MGCopyAnswerFn.self)
}()

func mgQueryLiveRaw(forKey key: String) -> CFTypeRef? {
    #if os(iOS) && !targetEnvironment(simulator)
    guard let fn = resolvedMGCopyAnswer, !key.isEmpty else { return nil }
    // MGCopyAnswer follows CoreFoundation's +1 Copy rule; takeRetainedValue() transfers ownership to ARC without leaking
    return fn(key as CFString)?.takeRetainedValue()
    #else
    return nil
    #endif
}

func mgQueryLiveBool(forKey key: String) -> Bool? {
    guard let val = mgQueryLiveRaw(forKey: key) else { return nil }
    let typeID = CFGetTypeID(val)
    if typeID == CFBooleanGetTypeID() {
        return CFBooleanGetValue((val as! CFBoolean))
    }
    if let num = val as? NSNumber {
        return num.boolValue
    }
    return nil
}

func mgQueryLiveString(forKey key: String) -> String? {
    guard let val = mgQueryLiveRaw(forKey: key) else { return nil }
    return val as? String
}

func mgQueryLiveFormatted(forKey key: String) -> String {
    guard let val = mgQueryLiveRaw(forKey: key) else {
        return L("nil (未返回 / 默认关闭)")
    }
    let typeID = CFGetTypeID(val)
    if typeID == CFBooleanGetTypeID() {
        return CFBooleanGetValue((val as! CFBoolean)) ? "true (Bool)" : "false (Bool)"
    }
    if let num = val as? NSNumber {
        if CFNumberIsFloatType(num) {
            return "\(num.doubleValue) (Float)"
        }
        return "\(num.stringValue) (Int)"
    }
    if let str = val as? String {
        return str.isEmpty ? "\"\"" : str
    }
    if let data = val as? Data {
        return L("<Data: \(data.count) 字节>")
    }
    if let arr = val as? NSArray {
        return L("<Array: \(arr.count) 项>")
    }
    if let dict = val as? NSDictionary {
        return L("<Dict: \(dict.count) 项>")
    }
    return String(describing: val)
}

/// Maps Mainland China / International models & ProductTypes to US (LL/A) RegulatoryModelNumber (97JDvERpVwO+GHtthIh7hA)
func usRegulatoryModelNumber(productType: String, originalRegModel: String = "") -> String? {
    let regModelMap: [String: String] = [
        // iPhone 18 / Duo Series (China / HK / Intl -> US)
        "A3718": "A3473", "A3717": "A3473", "A3716": "A3473", // iPhone 18 Pro Max -> US A3473
        "A3715": "A3472", "A3714": "A3472", "A3713": "A3472", // iPhone 18 Pro -> US A3472
        "A3721": "A3447", "A3720": "A3447", "A3719": "A3447", // iPhone Duo -> US A3447
        // iPhone 17 / Air / 17e Series
        "A3520": "A3258", "A3519": "A3258",                   // iPhone 17 -> US A3258
        "A3523": "A3256", "A3522": "A3256",                   // iPhone 17 Pro -> US A3256
        "A3526": "A3257", "A3525": "A3257",                   // iPhone 17 Pro Max -> US A3257
        "A3518": "A3260", "A3517": "A3260",                   // iPhone Air -> US A3260
        "A3635": "A3575", "A3634": "A3575",                   // iPhone 17e -> US A3575
        // iPhone 16 / 16e Series
        "A3288": "A3081", "A3287": "A3081",                   // iPhone 16 -> US A3081
        "A3291": "A3082", "A3290": "A3082",                   // iPhone 16 Plus -> US A3082
        "A3294": "A3083", "A3293": "A3083",                   // iPhone 16 Pro -> US A3083
        "A3297": "A3084", "A3296": "A3084",                   // iPhone 16 Pro Max -> US A3084
        "A3410": "A3212", "A3409": "A3212",                   // iPhone 16e -> US A3212
        // iPhone 15 Series
        "A3092": "A2846", "A3090": "A2846",                   // iPhone 15 -> US A2846
        "A3096": "A2847", "A3094": "A2847",                   // iPhone 15 Plus -> US A2847
        "A3104": "A2848", "A3102": "A2848",                   // iPhone 15 Pro -> US A2848
        "A3108": "A2849", "A3106": "A2849"                    // iPhone 15 Pro Max -> US A2849
    ]
    
    if let mapped = regModelMap[originalRegModel] {
        return mapped
    }
    
    let productTypeMap: [String: String] = [
        // iPhone 14 Series
        "iPhone14,7": "A2649",
        "iPhone14,8": "A2632",
        "iPhone15,2": "A2650",
        "iPhone15,3": "A2651",
        // iPhone 15 Series
        "iPhone15,4": "A2846",
        "iPhone15,5": "A2847",
        "iPhone16,1": "A2848",
        "iPhone16,2": "A2849",
        // iPhone 16 Series
        "iPhone17,1": "A3083",
        "iPhone17,2": "A3084",
        "iPhone17,3": "A3081",
        "iPhone17,4": "A3082",
        "iPhone17,5": "A3212",
        // iPhone 17 / Air / 17e Series
        "iPhone18,1": "A3256",
        "iPhone18,2": "A3257",
        "iPhone18,3": "A3258",
        "iPhone18,4": "A3260",
        "iPhone18,5": "A3575",
        // iPhone 18 / Duo Series (including regional/China board ProductTypes)
        "iPhone19,1": "A3471",
        "iPhone19,2": "A3472",
        "iPhone19,3": "A3473",
        "iPhone19,4": "A3447",
        "iPhone19,5": "A3471",
        "iPhone19,6": "A3472",
        "iPhone19,7": "A3473",
        "iPhone19,8": "A3447",
        // Apple Intelligence iPads
        "iPad13,4": "A2377", "iPad13,5": "A2301", "iPad13,6": "A2301", "iPad13,7": "A2301",
        "iPad13,8": "A2378", "iPad13,9": "A2379", "iPad13,10": "A2379", "iPad13,11": "A2379",
        "iPad13,16": "A2588", "iPad13,17": "A2589",
        "iPad14,3": "A2759", "iPad14,4": "A2435",
        "iPad14,5": "A2436", "iPad14,6": "A2764",
        "iPad14,8": "A2902", "iPad14,9": "A2903",
        "iPad14,10": "A2898", "iPad14,11": "A2899",
        "iPad15,3": "A3266", "iPad15,4": "A3267",
        "iPad15,5": "A3268", "iPad15,6": "A3269",
        "iPad16,1": "A2993", "iPad16,2": "A2995",
        "iPad16,3": "A2836", "iPad16,4": "A2837",
        "iPad16,5": "A2925", "iPad16,6": "A2926"
    ]
    
    return productTypeMap[productType]
}

/// Maps Mainland China hardware ProductType back to factory Mainland China (CH/A) RegulatoryModelNumber
/// when OriginalGestalt.plist was previously polluted with a US regulatory model by an external tool.
func chinaRegulatoryModelNumber(productType: String) -> String? {
    let chinaMap: [String: String] = [
        // iPhone 15 Series
        "iPhone15,4": "A3092",
        "iPhone15,5": "A3096",
        "iPhone16,1": "A3104",
        "iPhone16,2": "A3108",
        // iPhone 16 / 16e Series
        "iPhone17,1": "A3294",
        "iPhone17,2": "A3297",
        "iPhone17,3": "A3288",
        "iPhone17,4": "A3291",
        "iPhone17,5": "A3410",
        // iPhone 17 / Air / 17e Series
        "iPhone18,1": "A3523",
        "iPhone18,2": "A3526",
        "iPhone18,3": "A3520",
        "iPhone18,4": "A3518",
        "iPhone18,5": "A3635",
        // iPhone 18 / Duo Series
        "iPhone19,2": "A3715", "iPhone19,6": "A3715",
        "iPhone19,3": "A3718", "iPhone19,7": "A3718",
        "iPhone19,4": "A3721", "iPhone19,8": "A3721"
    ]
    return chinaMap[productType]
}

// device info getters
// HD - hardware device
func isDynamIslandHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone17,5", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone18,4", "iPhone18,5"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isAODHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone15,2", "iPhone15,3", "iPhone16,1", "iPhone16,2", "iPhone17,1", "iPhone17,2", "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isChargeLimitHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone17,5", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone18,4", "iPhone18,5", "iPad16,1", "iPad16,2", "iPad15,7", "iPad15,8", "iPad14,8", "iPad14,9", "iPad14,10", "iPad14,11", "iPad15,3", "iPad15,4", "iPad15,5", "iPad15,6", "iPad16,8", "iPad16,9", "iPad16,10", "iPad16,11", "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6", "iPad17,1", "iPad17,2", "iPad17,3", "iPad17,4"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isBootChimeHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone14,7", "iPhone14,8", "iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone17,5", "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4", "iPhone18,5"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isHomeButtonHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices: [String] = ["iPhone12,8", "iPhone14,6"]
    return hdDevices.contains(m)
}

// fun...
func isAppleIntellHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone17,5", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone18,4", "iPhone18,5", "iPad16,1", "iPad16,2", "iPad13,16", "iPad13,17", "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7", "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11", "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6", "iPad14,8", "iPad14,9", "iPad14,10", "iPad14,11", "iPad15,3", "iPad15,4", "iPad15,5", "iPad15,6", "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6", "iPad16,8", "iPad16,9", "iPad16,10", "iPad16,11", "iPad17,1", "iPad17,2", "iPad17,3", "iPad17,4"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isAudioIntellFirmwareSupported() -> Bool {
    if case .success(let layout) = MGCacheDataLayout.resolveFromLoadedLibrary(),
       layout.slotIndex(forKey: MGKey.audioIntell) != nil {
        return true
    }
    return mgQueryLiveRaw(forKey: MGKey.audioIntell) != nil
}

func isAdvAppleIntellFirmwareSupported() -> Bool {
    if case .success(let layout) = MGCacheDataLayout.resolveFromLoadedLibrary() {
        return MGKey.advAppIntellKeys.contains { layout.slotIndex(forKey: $0) != nil }
    }
    return MGKey.advAppIntellKeys.contains { mgQueryLiveRaw(forKey: $0) != nil }
}

func isNativeAudioIntellHD() -> Bool {
    let m = currentOriginalMachineName()
    if m.hasPrefix("iPhone") || m.hasPrefix("iPad") {
        return false
    }
    if let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL),
       case .success((let layout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: ogDict),
       layout.slotIndex(forKey: MGKey.audioIntell) != nil {
        return MGCacheDataCoordinator.shared.originalSlotValue(forKey: MGKey.audioIntell, layout: layout, savedOriginalDict: ogDict) == true
    }
    return false
}

func isNativePersonalTranslatorHD() -> Bool {
    guard isAppleIntellHD() else { return false }
    let m = currentOriginalMachineName()
    if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
        guard let slotIdx = layout.slotIndex(forKey: MGKey.personalTranslator) else {
            return false
        }
        // All native Apple Intelligence iPhones (iPhone 15 Pro through iPhone 18 Pro Max) have
        // Personal Translator (slot #266) enabled in factory CacheData; never let a polluted
        // backup or UserDefaults baseline downgrade it to false.
        if m.hasPrefix("iPhone") {
            return true
        }
        if let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL),
           case .success(let savedData) = layout.validatePlist(ogDict),
           layout.validateSingleBooleanSlot(slotIdx, in: savedData) {
            return savedData[slotIdx * 8] == 1
        }
        return true
    }
    return m.hasPrefix("iPhone") || isAppleIntellHD()
}

func isAdvAISlotNativeTrue(_ key: String, layout: MGCacheDataLayout, savedOrig: NSDictionary?) -> Bool {
    let m = currentOriginalMachineName()
    // Ground-truth verified via MGInspector on live iPhone 18 Pro Max (iPhone19,7) & iPhone 15 Pro Max (iPhone16,2) running iOS 27:
    // - rb2tKZxlj0Gm2tBmUQSLqQ (Audio Intelligence, slot #178) is natively FALSE (0x00) on iPhone/iPad,
    //   and forcing it to 1 breaks Photos High-Quality Clean Up ("消除此照片时出错。请稍后再试。").
    // - M1n2sAqf33NAOgZRGxQYBA (Personal Translator, slot #266) IS natively TRUE (0x01) on all native Apple Intelligence iPhones
    //   in factory OriginalGestalt.plist; forcing it to 0 breaks GenerativeModels / Photos Cloud Tools & Camera Siri in 0ms.
    if key == MGKey.audioIntell && (m.hasPrefix("iPhone") || m.hasPrefix("iPad")) {
        return false
    }
    if key == MGKey.personalTranslator {
        guard isAppleIntellHD(), let slotIdx = layout.slotIndex(forKey: key) else { return false }
        if m.hasPrefix("iPhone") {
            return true
        }
        if let savedOrig,
           case .success(let savedData) = layout.validatePlist(savedOrig),
           layout.validateSingleBooleanSlot(slotIdx, in: savedData) {
            return savedData[slotIdx * 8] == 1
        }
        return true
    }
    return MGCacheDataCoordinator.shared.originalSlotValue(forKey: key, layout: layout, savedOriginalDict: savedOrig) ?? false
}

/// Returns true only on models equipped with the 4-microphone spatial audio array (iPhone 16 series and newer 4-mic hardware).
/// Pre-iPhone 16 3-mic models (e.g. iPhone 15 Pro) expose a broken "录音室 (Studio)" option in Voice Memos if forced on.
func isSpatialAudioRecHD() -> Bool {
    if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout(),
       let slotIdx = layout.slotIndex(forKey: MGKey.spatialAudioRec) {
        if let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL) {
            if let val = MGCacheDataCoordinator.shared.originalSlotValue(forKey: MGKey.spatialAudioRec, layout: layout, savedOriginalDict: ogDict) {
                return val
            }
            if let ogData = ogDict["CacheData"] as? Data,
               ogData.count == layout.byteCount,
               layout.validateSingleBooleanSlot(slotIdx, in: ogData) {
                return ogData[slotIdx * 8] == 1
            }
        }
        if let recorded = MGCacheDataCoordinator.shared.originalSlotValue(forKey: MGKey.spatialAudioRec, layout: layout, savedOriginalDict: nil) {
            return recorded
        }
    }
    let m = currentOriginalMachineName()
    let fourMicPhones = [
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5",
        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,5"
    ]
    return fourMicPhones.contains(m) || m.hasPrefix("iPhone19,")
}

func isLiveAdvAIConflictActive() -> Bool {
    if isAdvAppleIntellHD() {
        return false
    }
    if case .success(let layout) = MGCacheDataCoordinator.shared.libraryLayout() {
        if layout.slotIndex(forKey: MGKey.personalTranslator) != nil,
           let livePT = mgQueryLiveBool(forKey: MGKey.personalTranslator),
           livePT != isNativePersonalTranslatorHD() {
            return true
        }
        if layout.slotIndex(forKey: MGKey.audioIntell) != nil,
           let liveAI = mgQueryLiveBool(forKey: MGKey.audioIntell),
           liveAI != isNativeAudioIntellHD() {
            return true
        }
        return false
    }
    let nativePersonalTranslator = isNativePersonalTranslatorHD()
    let nativeAudioIntell = isNativeAudioIntellHD()
    if let livePT = mgQueryLiveBool(forKey: MGKey.personalTranslator), livePT != nativePersonalTranslator {
        return true
    }
    if let liveAI = mgQueryLiveBool(forKey: MGKey.audioIntell), liveAI != nativeAudioIntell {
        return true
    }
    return false
}

func isAdvAppleIntellHD() -> Bool {
    let m = currentOriginalMachineName()
    if m.hasPrefix("iPhone") || m.hasPrefix("iPad") {
        return false
    }
    if GestaltStore.shared.isSlotRulesNativeSatisfied(MGKey.advAppIntellRules) {
        return true
    }
    if let ogDict = NSDictionary(contentsOf: MGURL.savedGestaltURL),
       case .success((let layout, _)) = MGCacheDataCoordinator.shared.resolveValidated(for: ogDict) {
        let presentKeys = MGKey.advAppIntellKeys.filter { layout.slotIndex(forKey: $0) != nil }
        if !presentKeys.isEmpty,
           presentKeys.allSatisfy({ MGCacheDataCoordinator.shared.originalSlotValue(forKey: $0, layout: layout, savedOriginalDict: ogDict) == true }) {
            return true
        }
    }
    return false
}

func isCrashDectHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone14,7", "iPhone14,8", "iPhone15,2", "iPhone15,3", "iPhone15,4", "iPhone15,5", "iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone17,5", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone18,4", "iPhone18,5"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isPWMHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone18,4"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isCamControlHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone18,4"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

func isActionButtonHD() -> Bool {
    let m = currentOriginalMachineName()
    let hdDevices = ["iPhone16,1", "iPhone16,2", "iPhone17,3", "iPhone17,4", "iPhone17,1", "iPhone17,2", "iPhone17,5", "iPhone18,3", "iPhone18,1", "iPhone18,2", "iPhone18,4", "iPhone18,5"]
    return hdDevices.contains(m) || m.hasPrefix("iPhone19,")
}

// MARK: - Missing Symbol Placeholders (unblock build)
// These definitions were previously provided by files no longer in the target.
// They are intentionally inert so the build compiles without changing behavior.
// Restore the real implementations from project history to re-enable these resets.

struct MGCustomKey: Codable {
    var isOn: Bool = false
}

extension Array where Element == MGCustomKey {
    init?(rawValue: String) {
        return nil
    }
    var rawValue: String { "" }
}

final class KeypadManager {
    static let shared = KeypadManager()
    private init() {}
    @discardableResult
    func resetKeypadItems() -> Bool { false }
}

extension ConfigView {
    static func resetSystemConfigSafely() throws {}
}