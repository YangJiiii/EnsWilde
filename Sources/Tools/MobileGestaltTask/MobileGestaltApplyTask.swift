//
//  MobileGestaltApplyTask.swift
//  EnsWilde
//

import Foundation
import UIKit
import Darwin

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    private static func ensureAccess() throws {
        let dir = MGURL.fsGestaltURL.deletingLastPathComponent().path
        if wq.hasActiveAccess(path: dir) { return }
        let (ok, handle, msg) = wq.grantAccess(path: dir)
        guard ok, handle > 0 else { throw NSError(domain: "MG", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]) }
    }

    static func applyGestalt(store: GestaltStore, onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw NSError(domain: "MG", code: -404, userInfo: [NSLocalizedDescriptionKey: "MobileGestalt cache is missing. Please RESPIRING or REBOOT your device to let iOS regenerate it before applying."])
        }
        
        onLogUpdate("[MG] Đang đọc file MobileGestalt hiện tại...")
        let liveData = try Data(contentsOf: URL(fileURLWithPath: onDeviceMGPath))
        guard let liveDict = try PropertyListSerialization.propertyList(from: liveData, options: [.mutableContainersAndLeaves], format: nil) as? NSMutableDictionary else {
            throw NSError(domain: "MG", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to parse live MobileGestalt"])
        }
        
        let candidateDict = NSMutableDictionary(dictionary: liveDict)
        
        onLogUpdate("[MG] Đang đồng bộ CacheData (raw byte diff)...")
        if let liveCacheData = liveDict["CacheData"] as? Data,
           let storeCacheData = store.mgCurrentDict["CacheData"] as? Data,
           liveCacheData.count == storeCacheData.count {
            
            var patchedData = liveCacheData
            var patchedBytes = 0
            
            for i in 0..<patchedData.count {
                if patchedData[i] != storeCacheData[i] {
                    patchedData[i] = storeCacheData[i]
                    patchedBytes += 1
                }
            }
            
            candidateDict["CacheData"] = patchedData
            onLogUpdate("[MG] Đã vá \(patchedBytes) byte trong CacheData.")
        } else {
            onLogUpdate("[MG] ⚠️ Kích thước CacheData không khớp, bỏ qua vá CacheData.")
        }
        
        onLogUpdate("[MG] Đang đồng bộ CacheExtra...")
        if let liveExtra = liveDict["CacheExtra"] as? NSMutableDictionary,
           let storeExtra = store.mgCurrentDict["CacheExtra"] as? NSDictionary {
            
            let allowedExtraKeys = [
                MGKey.artwork, MGKey.prodType, MGKey.regionCode, MGKey.regionSysconfig,
                MGKey.regModelNumber, MGKey.modelNameOuter1, MGKey.modelNameOuter2,
                MGKey.liquidGlassLowPower, MGKey.island, MGKey.AOTime, MGKey.AOD,
                MGKey.AODVibrancy, MGKey.chargeLim, MGKey.bootChime, MGKey.intInstall,
                MGKey.intBuild, MGKey.srd, MGKey.crashDet, MGKey.pwm, MGKey.appPencil,
                MGKey.camButton, MGKey.grapPefr, MGKey.actButton, MGKey.tapToWake,
                MGKey.stageMgr
            ] + MGKey.appIntellAllKeys + MGKey.ipadosCacheEx
            
            for key in allowedExtraKeys {
                if let newVal = storeExtra[key] {
                    liveExtra[key] = newVal
                } else {
                    liveExtra.removeObject(forKey: key)
                }
            }
            
            let blockedKeys = ["RegionInfo", "zHeENZu+wbg7PUprwNwBWg", "green-tea", "not-green-tea", "wapi"]
            for blocked in blockedKeys {
                liveExtra.removeObject(forKey: blocked)
            }
            
            candidateDict["CacheExtra"] = liveExtra
        }
        
        let finalData = try PropertyListSerialization.data(fromPropertyList: candidateDict, format: .binary, options: 0)
        onLogUpdate("[MG] Kích thước file mới: \(finalData.count) bytes (Cũ: \(liveData.count) bytes)")
        
        onLogUpdate("[MG] Đang ghi đè file (pwrite + F_FULLFSYNC)...")
        let fd = open(onDeviceMGPath, O_RDWR)
        guard fd >= 0 else {
            throw NSError(domain: "MG", code: -20, userInfo: [NSLocalizedDescriptionKey: "Không thể mở file để ghi."])
        }
        defer { close(fd) }

        let oldSize = lseek(fd, 0, SEEK_END)
        
        let written = finalData.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return pwrite(fd, base, finalData.count, 0)
        }
        
        guard written == finalData.count else {
            throw NSError(domain: "MG", code: -21, userInfo: [NSLocalizedDescriptionKey: "Lỗi pwrite. Ghi được \(written)/\(finalData.count) bytes."])
        }
        
        if oldSize > off_t(finalData.count) {
            ftruncate(fd, off_t(finalData.count))
        }
        
        if fcntl(fd, F_FULLFSYNC) == -1 {
            fsync(fd)
            onLogUpdate("[MG] ⚠️ F_FULLFSYNC thất bại, dùng fsync thay thế.")
        } else {
            onLogUpdate("[MG] ✅ F_FULLFSYNC thành công (Đã ép xuống ổ cứng).")
        }
        
        onLogUpdate("[MG] 🎉 GHI THÀNH CÔNG. Hãy TẮT NGUỒN (Hard Reboot) để iOS nạp lại cấu hình.")
    }

    static func restoreGestalt(onLogUpdate: @escaping (String) -> Void) async throws {
        try ensureAccess()
        if FileManager.default.fileExists(atPath: onDeviceMGPath) {
            try FileManager.default.removeItem(atPath: onDeviceMGPath)
            onLogUpdate("[MG] ✅ Đã xóa MobileGestalt cache. Hãy Respring để iOS tạo lại file gốc.")
        }
    }
}