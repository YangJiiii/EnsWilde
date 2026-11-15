//
//  MGCacheLayout.swift
//  EnsWilde
//

import Foundation

fileprivate extension String {
    var loc: String { L(self) }
}

struct MGSlotDescriptorInfo: Identifiable, Equatable, Sendable {
    var id: String { "\(slotIndex):\(obfuscatedKey)" }
    let obfuscatedKey: String
    let slotIndex: Int
    let queryType: UInt32

    var valueOffset: Int? { slotIndex >= 0 ? slotIndex * 8 : nil }

    func validityOffset(slotCount: Int) -> Int? {
        guard slotIndex >= 0 else { return nil }
        return slotCount * 8 + slotIndex
    }
}

struct MGCacheDataLayout: Codable, Equatable, Sendable {
    static let greenTeaKey = "iyfxmLogGVIaH7aEgqwcIA"
    static let notGreenTeaKey = "4snMZS8LJkSctKypt2m+xA"
    static let wapiKey = "hiHut/WR+B9Lx/vd0WyeNg"

    static let audioMixKey = "aVL5GE3tx0LSCI/ErfrJGA"
    static let spatialAudioRecKey = "X6NGcYcvHmbqlR8hLXASJA"
    static let spatialFaceTimeAudioKey = "/EVOCjM/Nmb2roP5ebtEFA"
    static let responsiveShutterKey = "gQDt76Te0SPw7N8oTLrBFw"
    static let hypertensionNotifKey = "4fh9efw4o1yaFqkXNCXoeA"

    static let appIntellKey = "A62OafQ85EJAiiqKn4agtg"
    static let photosCleanUpKey = "XNCjqOupLM/S8fNyxRNQTA"
    static let handwritingSynthKey = "YgYIIViDt1kgzyIsIV61vA"
    static let audioIntellKey = "rb2tKZxlj0Gm2tBmUQSLqQ"
    static let personalTranslatorKey = "M1n2sAqf33NAOgZRGxQYBA"

    static let islandKey = "YlEtTtHlNesRBMal1CqRaA"
    static let aodKey = "2OOJf1VhaM7NxfRok3HbWQ"
    static let aoTimeKey = "j8/Omm6s1lsmTDFsXjsBfA"
    static let aodVibrancyKey = "ykpu7qyhqFweVMKtxNylWA"
    static let liquidGlassLowPowerKey = "SAGvsp6O6kAQ4fEfDJpC4Q"
    static let chargeLimKey = "37NVydb//GP/GrhuTN+exg"
    static let bootChimeKey = "QHxt+hGLaBPbQJbXiUJX3w"
    static let crashDetKey = "HCzWusHQwZDea6nNhaKndw"
    static let pwmKey = "6IejgN+1Fmu5/QrZFOIeNw"
    static let appPencilKey = "yhHcB0iH0d1XzPO/CFd3ow"
    static let camButtonKey = "CwvKxM2cEogD3p+HYgaW0Q"
    static let actButtonKey = "cT44WE1EohiwRzhsZ8xEsw"
    static let tapToWakeKey = "yZf3GTRMGTuwSV/lD7Cagw"
    static let stageMgrKey = "qeaj75wk3HF4DwQ8qbIi7g"

    // IPadOS Keys
    static let ipadModeKey = "uKc7FPnEO++lVhHWHFlGbQ"
    static let medusaFloatingKey = "mG0AnH/Vy1veoqoLRAIgTA"
    static let medusaOverlayKey = "UCG5MkVahJxG1YULbbd5Bg"
    static let medusaPinnedKey = "ZYqko/XM5zD3XBfN5RmaXA"
    static let medusaPipKey = "nVh/gwNpy7Jv1NOk00CMrw"
    static let deviceClassNumberKey = "mtrAoWJ3gsq+I90ZnQ0vQw"

    static let shutterRelaxationKey = "P4ZJVy/zYuLy4ejRKP+0DA"
    static let shutterKeyboardMutePreserveKey = "bGUN8lS6sYzy3xhePubp8A"
    static let shutterLegacyMutePreserveKey = "Bim3FC83Te8QX1kfSpqYKQ"
    static let concurrentHPLPMicsKey = "dI30ovtFUIeLioNQKDMbGQ"
    static let photosLocalLightKey = "m9ORTKMgu9A+zF+A61Zz5A"
    static let toneMappingKey = "Lcu6Zck+C/+AMO8qULacDw"
    static let hdrDeferredProcessingKey = "JkZlE8z9YwHjE1hnbMhcgA"
    static let spatialOverCaptureKey = "SjQQ07G8UacM7E69G7dPbg"
    static let stereoAudioRecKey = "YlK+0xmxNWhNn/+r8SM8kA"
    static let p3VideoRecKey = "1eBwtCIwbIDdC80wiyzfow"
    static let touchSensitiveCamControlKey = "lyJZrSDc8J8eQ5Zb7A1Rvw"
    static let hardwareDetentsKey = "V9pLLbPQhyb75bbdTioZVw"
    static let cameraHapticsKey = "XriAxQ+JY1z5nt5f3ftXVw"
    static let legacyBatteryInfoKey = "Rq0MF/w+gXM66Ii4fkWOzg"
    static let legacyDynamicEndOfChargeKey = "nfR1IphTGCaoFNu3NrCtWQ"
    static let highLuminanceAODKey = "7brdL5xrEUWnlF9C0kdg5A"
    static let aodFlipbookKey = "aoJSd/MXk7M40NgXTM6x+g"
    static let carPlay2Key = "PR+xeEtTAiUN0R25+EYGfw"
    static let touchDelivery120HzKey = "2OK50OGmkXM1ospsh766WQ"
    static let hearingAidEQKey = "SMgTCc2v9AU2ziIHRX8qww"
    static let hearingAidLEKey = "RyXm3yMC4ejlFvwlEI509w"
    static let hearingAidPowerRedKey = "u3c0R+31Df4SUTHrICQkTg"
    static let breathingDisturbancesKey = "e0HV2blYUDBk/MsMEQACNA"
    static let usBloodOxygenKey = "E4vGMChwcVRKD8hMVxnRvg"
    static let workoutUltraKey = "fu+4kyf8VcMBtgbMyJlLtg"
    static let timeInDaylightKey = "8gVfz9/8R1OtWBBtI0o/+Q"
    static let siriHubKey = "waGD2UTpntjbDXD1r3oALQ"
    static let onDeviceSiriKey = "O/7gbXWA5X2IRPVtDRU+bw"
    static let modelPruningKey = "m4xs4mhvxnAopYrApoLDMw"

    static let optionalFeatureSlotKeys: Set<String> = [
        audioMixKey, spatialAudioRecKey, spatialFaceTimeAudioKey, responsiveShutterKey, hypertensionNotifKey,
        appIntellKey, photosCleanUpKey, handwritingSynthKey, audioIntellKey, personalTranslatorKey,
        islandKey, aodKey, aoTimeKey, aodVibrancyKey, liquidGlassLowPowerKey, chargeLimKey, bootChimeKey,
        crashDetKey, pwmKey, appPencilKey, camButtonKey, actButtonKey, tapToWakeKey, stageMgrKey,
        ipadModeKey, medusaFloatingKey, medusaOverlayKey, medusaPinnedKey, medusaPipKey,
        shutterRelaxationKey, shutterKeyboardMutePreserveKey, shutterLegacyMutePreserveKey, concurrentHPLPMicsKey,
        photosLocalLightKey, toneMappingKey, hdrDeferredProcessingKey, spatialOverCaptureKey, stereoAudioRecKey,
        p3VideoRecKey, touchSensitiveCamControlKey, hardwareDetentsKey, cameraHapticsKey, legacyBatteryInfoKey,
        legacyDynamicEndOfChargeKey, highLuminanceAODKey, aodFlipbookKey, carPlay2Key, touchDelivery120HzKey,
        hearingAidEQKey, hearingAidLEKey, hearingAidPowerRedKey, breathingDisturbancesKey, usBloodOxygenKey,
        workoutUltraKey, timeInDaylightKey, siriHubKey, onDeviceSiriKey, modelPruningKey
    ]

    static let mediaHealthSlotKeys: Set<String> = [
        audioMixKey, spatialAudioRecKey, spatialFaceTimeAudioKey, responsiveShutterKey, hypertensionNotifKey
    ]

    let uuid: String
    let slotCount: Int
    let greenTeaIndex: Int
    let notGreenTeaIndex: Int
    let wapiIndex: Int?
    var featureSlotIndices: [String: Int] = [:]

    var byteCount: Int { slotCount * 9 }
    var greenTeaOffset: Int { greenTeaIndex * 8 }
    var notGreenTeaOffset: Int { notGreenTeaIndex * 8 }
    var wapiOffset: Int? { wapiIndex.map { $0 * 8 } }

    func slotIndex(forKey key: String) -> Int? {
        if key == Self.greenTeaKey { return greenTeaIndex }
        if key == Self.notGreenTeaKey { return notGreenTeaIndex }
        if key == Self.wapiKey { return wapiIndex }
        return featureSlotIndices[key]
    }

    func valueOffset(forKey key: String) -> Int? {
        return slotIndex(forKey: key).map { $0 * 8 }
    }

    func validityOffset(for slotIndex: Int) -> Int {
        return slotCount * 8 + slotIndex
    }

    var permittedMutableOffsets: Set<Int> {
        var set: Set<Int> = [greenTeaOffset, notGreenTeaOffset]
        if let wOff = wapiOffset {
            set.insert(wOff)
        }
        for (_, slotIdx) in featureSlotIndices where (0..<slotCount).contains(slotIdx) {
            set.insert(slotIdx * 8)
        }
        return set
    }

    static func resolveFromLoadedLibrary() -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = MGCopyLoadedMobileGestaltImage() else {
            return .failure(.libraryUnavailable("Failed to read /usr/lib/libMobileGestalt.dylib sections from memory."))
        }
        return scan(image: image)
        #else
        return .failure(.libraryUnavailable("Not running on an actual iOS device. Binary CacheData modifications are disabled."))
        #endif
    }

    static func scan(image: [String: Any]) -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        guard let strings = image["strings"] as? Data,
              let addressNum = image["stringAddress"] as? NSNumber,
              let constants = image["constants"] as? [Data] else {
            return .failure(.malformedImage("System library image is missing required __cstring or __const sections."))
        }
        let extraUUIDs = (image["cfUUIDs"] as? [String]) ?? []
        return scan(
            strings: strings,
            stringAddress: addressNum.uint64Value,
            constants: constants,
            extraUUIDs: extraUUIDs
        )
    }

    static func scan(
        strings: Data,
        stringAddress: UInt64,
        constants: [Data],
        extraUUIDs: [String] = []
    ) -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        guard !strings.isEmpty,
              strings.count <= 32 * 1024 * 1024,
              stringAddress > 0,
              stringAddress <= UInt64.max - UInt64(strings.count),
              !constants.isEmpty,
              constants.count <= 8,
              constants.allSatisfy({ $0.count <= 32 * 1024 * 1024 }) else {
            return .failure(.malformedImage("Abnormal system library section size or address range. Resolution denied."))
        }

        var hashByAddress: [UInt64: String] = [:]
        var discoveredUUIDs = Set<String>()

        for u in extraUUIDs {
            if u.count == 36, let parsed = UUID(uuidString: u) {
                discoveredUUIDs.insert(parsed.uuidString.uppercased())
            }
        }

        strings.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuf.count
            var tokenStart = 0
            for idx in 0..<count where base[idx] == 0 {
                let len = idx - tokenStart
                if len == 22 {
                    var valid = true
                    for k in tokenStart..<idx {
                        let b = base[k]
                        if !((65...90).contains(b) || (97...122).contains(b) || (48...57).contains(b) || b == 43 || b == 47) {
                            valid = false
                            break
                        }
                    }
                    if valid {
                        let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 22)
                        hashByAddress[stringAddress + UInt64(tokenStart)] = String(decoding: slice, as: UTF8.self)
                    }
                } else if len == 36 {
                    let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 36)
                    if let text = String(bytes: slice, encoding: .utf8),
                       let parsedUUID = UUID(uuidString: text) {
                        discoveredUUIDs.insert(parsedUUID.uuidString.uppercased())
                    }
                }
                tokenStart = idx + 1
            }
        }

        guard !discoveredUUIDs.isEmpty else {
            return .failure(.uuidNotFound("Failed to find a unique CacheUUID in the system library. Modification denied."))
        }
        guard discoveredUUIDs.count == 1, let resolvedUUID = discoveredUUIDs.first else {
            return .failure(.ambiguousUUID("Multiple UUID candidates found in system library (\(discoveredUUIDs.count)). Refusing to guess offsets!"))
        }

        var positiveIndices = Set<Int>()
        var targetIndices: [String: Set<Int>] = [:]
        var targetAlignments: [String: Set<String>] = [:]
        let requiredKeys: Set<String> = [greenTeaKey, notGreenTeaKey, wapiKey]

        for (secID, secData) in constants.enumerated() where secData.count >= 64 {
            let scanErr: MGCacheResolutionError? = secData.withUnsafeBytes { raw -> MGCacheResolutionError? in
                for off in stride(from: 0, through: secData.count - 64, by: 8) {
                    let rawPtr = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt64.self))
                    let canonicalPtr = rawPtr & 0x0000_7FFF_FFFF_FFFF
                    guard let key = hashByAddress[canonicalPtr] else { continue }

                    let slotIdx = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3A, as: Int16.self)))
                    let queryType = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3C, as: UInt32.self))
                    guard (-1..<16384).contains(slotIdx), (1...11).contains(queryType) else { continue }

                    if slotIdx >= 0 { positiveIndices.insert(slotIdx) }

                    if requiredKeys.contains(key) {
                        guard queryType == 11, slotIdx >= 0 else {
                            return .invalidTargetDescriptor("Target key \(key) descriptor type (\(queryType)) or slot (\(slotIdx)) is not a valid boolean cache item.")
                        }
                        targetIndices[key, default: []].insert(slotIdx)
                        targetAlignments[key, default: []].insert("\(secID):\(off % 64)")
                    } else if optionalFeatureSlotKeys.contains(key), queryType == 11, slotIdx >= 0 {
                        targetIndices[key, default: []].insert(slotIdx)
                        targetAlignments[key, default: []].insert("\(secID):\(off % 64)")
                    }
                }
                return nil
            }
            if let scanErr { return .failure(scanErr) }
        }

        guard let maxSlotIndex = positiveIndices.max(), maxSlotIndex >= 1 else {
            return .failure(.descriptorTableNotFound("Failed to locate a valid MobileGestalt query descriptor table in the system library."))
        }
        let slotCount = maxSlotIndex + 1
        guard positiveIndices.count > slotCount / 2 else {
            return .failure(.sparseDescriptorTable("Abnormal descriptor table slot coverage (\(positiveIndices.count)/\(slotCount)). Resolution denied."))
        }

        guard let gtSet = targetIndices[greenTeaKey], gtSet.count == 1, let gtIdx = gtSet.first,
              let ngtSet = targetIndices[notGreenTeaKey], ngtSet.count == 1, let ngtIdx = ngtSet.first,
              gtIdx != ngtIdx,
              (0..<slotCount).contains(gtIdx),
              (0..<slotCount).contains(ngtIdx),
              let gtAlign = targetAlignments[greenTeaKey], gtAlign.count == 1,
              gtAlign == targetAlignments[notGreenTeaKey] else {
            return .failure(.invalidTargetDescriptor("Failed to uniquely determine green-tea / not-green-tea cache slots or table alignment mismatch. Modification denied."))
        }

        var resolvedWapiIdx: Int? = nil
        if let wapiSet = targetIndices[wapiKey] {
            guard wapiSet.count == 1,
                  let wIdx = wapiSet.first,
                  (0..<slotCount).contains(wIdx),
                  wIdx != gtIdx, wIdx != ngtIdx,
                  targetAlignments[wapiKey] == gtAlign else {
                return .failure(.invalidTargetDescriptor("wapi descriptor is ambiguous or alignment mismatch. Resolution denied."))
            }
            resolvedWapiIdx = wIdx
        }

        var resolvedFeatureSlots: [String: Int] = [:]
        var usedCoreSlots: Set<Int> = [gtIdx, ngtIdx]
        if let wIdx = resolvedWapiIdx { usedCoreSlots.insert(wIdx) }
        
        for fKey in optionalFeatureSlotKeys.sorted() {
            if let fSet = targetIndices[fKey], fSet.count == 1, let fIdx = fSet.first,
               (0..<slotCount).contains(fIdx), !usedCoreSlots.contains(fIdx),
               targetAlignments[fKey] == gtAlign {
                resolvedFeatureSlots[fKey] = fIdx
            }
        }

        return .success(MGCacheDataLayout(
            uuid: resolvedUUID,
            slotCount: slotCount,
            greenTeaIndex: gtIdx,
            notGreenTeaIndex: ngtIdx,
            wapiIndex: resolvedWapiIdx,
            featureSlotIndices: resolvedFeatureSlots
        ))
    }

    static func scanDescriptorsFromLoadedLibrary() -> [MGSlotDescriptorInfo] {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = MGCopyLoadedMobileGestaltImage(),
              let strings = image["strings"] as? Data,
              let addressNum = image["stringAddress"] as? NSNumber,
              let constants = image["constants"] as? [Data] else { return [] }
        
        let stringAddress = addressNum.uint64Value
        var hashByAddress: [UInt64: String] = [:]
        strings.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuf.count
            var tokenStart = 0
            for idx in 0..<count where base[idx] == 0 {
                let len = idx - tokenStart
                if len == 22 {
                    var valid = true
                    for k in tokenStart..<idx {
                        let b = base[k]
                        if !((65...90).contains(b) || (97...122).contains(b) || (48...57).contains(b) || b == 43 || b == 47) {
                            valid = false; break
                        }
                    }
                    if valid {
                        let slice = UnsafeBufferPointer(start: base.advanced(by: tokenStart), count: 22)
                        hashByAddress[stringAddress + UInt64(tokenStart)] = String(decoding: slice, as: UTF8.self)
                    }
                }
                tokenStart = idx + 1
            }
        }

        var expectedSecID: Int? = nil
        var expectedMod: Int? = nil
        for (secID, secData) in constants.enumerated() where secData.count >= 64 {
            secData.withUnsafeBytes { raw in
                for off in stride(from: 0, through: secData.count - 64, by: 8) {
                    let rawPtr = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt64.self))
                    let canonicalPtr = rawPtr & 0x0000_7FFF_FFFF_FFFF
                    if hashByAddress[canonicalPtr] == greenTeaKey {
                        let slotIdx = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3A, as: Int16.self)))
                        let queryType = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3C, as: UInt32.self))
                        if slotIdx >= 0 && queryType == 11 {
                            expectedSecID = secID; expectedMod = off % 64; break
                        }
                    }
                }
            }
            if expectedSecID != nil { break }
        }

        var results: [MGSlotDescriptorInfo] = []
        var seenKeys = Set<String>()
        for (secID, secData) in constants.enumerated() where secData.count >= 64 {
            if let expSec = expectedSecID, expSec != secID { continue }
            secData.withUnsafeBytes { raw in
                for off in stride(from: 0, through: secData.count - 64, by: 8) {
                    if let expMod = expectedMod, (off % 64) != expMod { continue }
                    let rawPtr = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt64.self))
                    let canonicalPtr = rawPtr & 0x0000_7FFF_FFFF_FFFF
                    guard let key = hashByAddress[canonicalPtr], !seenKeys.contains(key) else { continue }
                    let slotIdx = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3A, as: Int16.self)))
                    let queryType = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off + 0x3C, as: UInt32.self))
                    guard (-1..<16384).contains(slotIdx), (1...11).contains(queryType) else { continue }
                    seenKeys.insert(key)
                    results.append(MGSlotDescriptorInfo(obfuscatedKey: key, slotIndex: slotIdx, queryType: queryType))
                }
            }
        }
        return results
        #else
        return []
        #endif
    }

    func validatePlist(_ dict: NSDictionary, checkWapiSlot: Bool = false) -> Result<Data, MGCacheResolutionError> {
        guard (1...16384).contains(slotCount),
              (0..<slotCount).contains(greenTeaIndex),
              (0..<slotCount).contains(notGreenTeaIndex),
              greenTeaIndex != notGreenTeaIndex else {
            return .failure(.invalidTargetDescriptor("Cache slot index out of valid range."))
        }

        guard let plistUUID = dict["CacheUUID"] as? String, !plistUUID.isEmpty else {
            return .failure(.plistMismatch("MobileGestalt file is missing CacheUUID field. Modification denied."))
        }
        guard plistUUID.caseInsensitiveCompare(uuid) == .orderedSame else {
            return .failure(.plistMismatch("Cache file CacheUUID (\(plistUUID)) does not match system library (\(uuid)). Modification denied!"))
        }

        guard let cacheData = dict["CacheData"] as? Data else {
            return .failure(.plistMismatch("MobileGestalt file is missing binary CacheData field. Modification denied."))
        }
        guard cacheData.count == byteCount else {
            return .failure(.plistMismatch("CacheData length (\(cacheData.count) bytes) does not match exact length calculated by system library (\(byteCount) bytes, \(slotCount) slots). Modification denied!"))
        }

        var slotsToVerify = [greenTeaIndex, notGreenTeaIndex]
        if let wIdx = wapiIndex {
            if checkWapiSlot || validateSingleBooleanSlot(wIdx, in: cacheData) {
                slotsToVerify.append(wIdx)
            }
        } else if checkWapiSlot {
            return .failure(.invalidTargetDescriptor("Current system library did not resolve a valid wapi slot. Modification denied."))
        }

        for slotIdx in slotsToVerify {
            let valOff = slotIdx * 8
            let validOff = validityOffset(for: slotIdx)
            guard validOff < cacheData.count, valOff + 8 <= cacheData.count else {
                return .failure(.plistMismatch("Slot \(slotIdx) offset out of bounds. Modification denied."))
            }
            guard cacheData[validOff] == 1 else {
                let validOffHex = String(format: "%X", validOff)
                return .failure(.slotInvalid("Slot \(slotIdx) (validity offset 0x\(validOffHex)) is not marked as valid by the system (validity != 1). Modification denied!"))
            }
            guard cacheData[valOff] <= 1 else {
                let valOffHex = String(format: "%X", valOff)
                return .failure(.slotInvalid("Slot \(slotIdx) (offset 0x\(valOffHex)) current byte value (\(cacheData[valOff])) is not a valid boolean (0/1). Modification denied!"))
            }
            for pad in (valOff + 1)..<(valOff + 8) {
                guard cacheData[pad] == 0 else {
                    let padHex = String(format: "%X", pad)
                    return .failure(.slotInvalid("Slot \(slotIdx) padding byte is non-zero (offset 0x\(padHex) = \(cacheData[pad])). Modification denied!"))
                }
            }
        }

        if let extra = dict["CacheExtra"] as? NSDictionary {
            var forbiddenKeys = [Self.greenTeaKey, Self.notGreenTeaKey, "green-tea", "not-green-tea"]
            if checkWapiSlot {
                forbiddenKeys.append(contentsOf: [Self.wapiKey, "wapi"])
            }
            for k in forbiddenKeys where extra[k] != nil {
                return .failure(.conflictingCacheExtra("Detected overriding key \(k) in CacheExtra. CacheData modification denied for safety."))
            }
        }

        return .success(cacheData)
    }

    func validateSingleBooleanSlot(_ slotIdx: Int, in cacheData: Data) -> Bool {
        let valOff = slotIdx * 8
        let validOff = validityOffset(for: slotIdx)
        guard cacheData.count == byteCount,
              (0..<slotCount).contains(slotIdx),
              validOff < cacheData.count,
              valOff + 8 <= cacheData.count,
              cacheData[validOff] == 1,
              cacheData[valOff] <= 1 else { return false }
        return cacheData[(valOff + 1)..<(valOff + 8)].allSatisfy { $0 == 0 }
    }
}

enum MGCacheResolutionError: LocalizedError, Equatable {
    case libraryUnavailable(String)
    case malformedImage(String)
    case uuidNotFound(String)
    case ambiguousUUID(String)
    case descriptorTableNotFound(String)
    case sparseDescriptorTable(String)
    case invalidTargetDescriptor(String)
    case plistMismatch(String)
    case slotInvalid(String)
    case conflictingCacheExtra(String)
    case unauthorizedByteMutation(String)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let m), .malformedImage(let m), .uuidNotFound(let m),
             .ambiguousUUID(let m), .descriptorTableNotFound(let m), .sparseDescriptorTable(let m),
             .invalidTargetDescriptor(let m), .plistMismatch(let m), .slotInvalid(let m),
             .conflictingCacheExtra(let m), .unauthorizedByteMutation(let m):
            return m
        }
    }
}

struct MGCacheRecordedFlags: Codable, Equatable {
    let layoutUUID: String
    let cacheVersion: String
    let greenTea: Bool
    let notGreenTea: Bool
    let wapi: Bool?
    var extraSlots: [String: Bool]? = nil
}

struct MGCacheDataDiffDetail {
    let id: String
    let label: String
    let keyPath: String
    let beforeText: String
    let afterText: String
}

final class MGCacheDataCoordinator {
    static let shared = MGCacheDataCoordinator()

    private let defaultsKey = "mgRecordedOriginalCacheFlagsByUUID_v1"
    private let lock = NSLock()
    private var cachedVerifiedLayout: MGCacheDataLayout?
    private var cachedAllDescriptors: [MGSlotDescriptorInfo]?

    private init() {}

    func allDescriptors() -> [MGSlotDescriptorInfo] {
        lock.lock()
        if let existing = cachedAllDescriptors {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let scanned = MGCacheDataLayout.scanDescriptorsFromLoadedLibrary()
        if !scanned.isEmpty {
            lock.lock()
            cachedAllDescriptors = scanned
            lock.unlock()
        }
        return scanned
    }

    func libraryLayout() -> Result<MGCacheDataLayout, MGCacheResolutionError> {
        lock.lock()
        if let existing = cachedVerifiedLayout {
            lock.unlock()
            return .success(existing)
        }
        lock.unlock()

        let resolved = MGCacheDataLayout.resolveFromLoadedLibrary()
        if case .success(let layout) = resolved {
            lock.lock()
            cachedVerifiedLayout = layout
            lock.unlock()
        }
        return resolved
    }

    func resolveValidated(for dict: NSDictionary, checkWapiSlot: Bool = false) -> Result<(MGCacheDataLayout, Data), MGCacheResolutionError> {
        switch libraryLayout() {
        case .failure(let err):
            return .failure(err)
        case .success(let layout):
            switch layout.validatePlist(dict, checkWapiSlot: checkWapiSlot) {
            case .failure(let err):
                return .failure(err)
            case .success(let data):
                return .success((layout, data))
            }
        }
    }

    func recordBaselineIfNeeded(liveDict: NSDictionary, savedOriginalDict: NSDictionary?) {
        if let saved = savedOriginalDict,
           case .success((let layout, let savedData)) = resolveValidated(for: saved) {
            saveInitialFlagsIfAbsent(from: saved, data: savedData, layout: layout)
            return
        }
        if case .success((let layout, let liveData)) = resolveValidated(for: liveDict) {
            saveInitialFlagsIfAbsent(from: liveDict, data: liveData, layout: layout)
        }
    }

    private func saveInitialFlagsIfAbsent(from dict: NSDictionary, data: Data, layout: MGCacheDataLayout) {
        lock.lock()
        defer { lock.unlock() }
        var map = loadRecordedMap()
        let key = layout.uuid.uppercased()

        var extraMap: [String: Bool] = [:]
        let hwModel = currentOriginalMachineName()
        for (fKey, fSlot) in layout.featureSlotIndices where layout.validateSingleBooleanSlot(fSlot, in: data) {
            if fKey == MGCacheDataLayout.audioIntellKey && (hwModel.hasPrefix("iPhone") || hwModel.hasPrefix("iPad")) {
                extraMap[fKey] = false
            } else if fKey == MGCacheDataLayout.personalTranslatorKey && hwModel.hasPrefix("iPhone") {
                extraMap[fKey] = isAppleIntellHD()
            } else {
                extraMap[fKey] = (data[fSlot * 8] == 1)
            }
        }

        if var existing = map[key] {
            var currentExtra = existing.extraSlots ?? [:]
            var updated = false
            for (k, v) in extraMap where currentExtra[k] == nil {
                currentExtra[k] = v
                updated = true
            }
            if updated {
                existing.extraSlots = currentExtra
                map[key] = existing
                saveRecordedMap(map)
            }
            return
        }

        let gt = data[layout.greenTeaOffset] == 1
        let ngt = data[layout.notGreenTeaOffset] == 1
        var wapiVal: Bool? = nil
        if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: data) {
            wapiVal = (data[wIdx * 8] == 1)
        }
        let build = dict["CacheVersion"] as? String ?? ""
        map[key] = MGCacheRecordedFlags(
            layoutUUID: key, cacheVersion: build, greenTea: gt, notGreenTea: ngt, wapi: wapiVal, extraSlots: extraMap
        )
        saveRecordedMap(map)
    }

    func originalFlags(for layout: MGCacheDataLayout, savedOriginalDict: NSDictionary?) -> MGCacheRecordedFlags? {
        if let saved = savedOriginalDict, case .success(let savedData) = layout.validatePlist(saved) {
            let gt = savedData[layout.greenTeaOffset] == 1
            let ngt = savedData[layout.notGreenTeaOffset] == 1
            var wVal: Bool? = nil
            if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: savedData) {
                wVal = (savedData[wIdx * 8] == 1)
            }
            var extraMap: [String: Bool] = [:]
            for (fKey, fSlot) in layout.featureSlotIndices where layout.validateSingleBooleanSlot(fSlot, in: savedData) {
                extraMap[fKey] = (savedData[fSlot * 8] == 1)
            }
            let build = saved["CacheVersion"] as? String ?? ""
            return MGCacheRecordedFlags(
                layoutUUID: layout.uuid.uppercased(), cacheVersion: build, greenTea: gt, notGreenTea: ngt, wapi: wVal, extraSlots: extraMap
            )
        }
        return loadRecordedMap()[layout.uuid.uppercased()]
    }

    func originalSlotValue(forKey key: String, layout: MGCacheDataLayout, savedOriginalDict: NSDictionary?) -> Bool? {
        let hwModel = currentOriginalMachineName()
        if key == MGCacheDataLayout.audioIntellKey && (hwModel.hasPrefix("iPhone") || hwModel.hasPrefix("iPad")) {
            return false
        }
        if key == MGCacheDataLayout.personalTranslatorKey && hwModel.hasPrefix("iPhone") {
            return isAppleIntellHD()
        }
        if let saved = savedOriginalDict, case .success(let savedData) = layout.validatePlist(saved),
           let slotIdx = layout.slotIndex(forKey: key), layout.validateSingleBooleanSlot(slotIdx, in: savedData) {
            return savedData[slotIdx * 8] == 1
        }
        if key == MGCacheDataLayout.personalTranslatorKey { return isAppleIntellHD() }
        return loadRecordedMap()[layout.uuid.uppercased()]?.extraSlots?[key]
    }

    func clearRecordedBaselines() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func loadRecordedMap() -> [String: MGCacheRecordedFlags] {
        guard let raw = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: MGCacheRecordedFlags].self, from: raw) else { return [:] }
        return decoded
    }

    private func saveRecordedMap(_ map: [String: MGCacheRecordedFlags]) {
        if let encoded = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    func validateTransition(from beforeDict: NSDictionary, to afterDict: NSDictionary, using customLayout: MGCacheDataLayout? = nil) -> Result<Void, MGCacheResolutionError> {
        let beforeData = beforeDict["CacheData"] as? Data
        let afterData = afterDict["CacheData"] as? Data
        guard beforeData != afterData else { return .success(()) }

        let layout: MGCacheDataLayout
        if let customLayout { layout = customLayout }
        else {
            switch libraryLayout() {
            case .failure(let err): return .failure(err)
            case .success(let resolved): layout = resolved
            }
        }

        guard case .success(let validBefore) = layout.validatePlist(beforeDict),
              case .success(let validAfter) = layout.validatePlist(afterDict),
              validBefore.count == validAfter.count else {
            switch layout.validatePlist(afterDict) {
            case .failure(let err): return .failure(err)
            case .success:
                if case .failure(let err2) = layout.validatePlist(beforeDict) { return .failure(err2) }
                return .failure(.plistMismatch("CacheData validation failed before/after modification. Write denied."))
            }
        }

        let allowedOffsets = layout.permittedMutableOffsets
        if let wOff = layout.wapiOffset, validBefore[wOff] != validAfter[wOff] {
            if case .failure(let wErr) = layout.validatePlist(afterDict, checkWapiSlot: true) { return .failure(wErr) }
        }

        for (fKey, fSlot) in layout.featureSlotIndices {
            let fOff = fSlot * 8
            if validBefore[fOff] != validAfter[fOff] {
                guard layout.validateSingleBooleanSlot(fSlot, in: validBefore),
                      layout.validateSingleBooleanSlot(fSlot, in: validAfter) else {
                    return .failure(.slotInvalid("Feature slot \(fSlot) (\(fKey)) failed 8-byte boolean validity check. Modification denied!"))
                }
            }
        }

        for idx in validBefore.indices where validBefore[idx] != validAfter[idx] {
            guard allowedOffsets.contains(idx) else {
                return .failure(.unauthorizedByteMutation(String(format: "Detected unauthorized unrelated cache byte modification (offset 0x%X: 0x%02X -> 0x%02X). Write aborted!".loc, idx, validBefore[idx], validAfter[idx])))
            }
        }

        return .success(())
    }

    static func featureSlotMeta(forKey key: String) -> (id: String, label: String, trueHint: String, falseHint: String) {
        switch key {
        case MGCacheDataLayout.audioMixKey: return ("audio-mix", "Photos & Camera Audio Mix", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.spatialAudioRecKey: return ("spatial-audio-rec", "Spatial Audio Recording", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.spatialFaceTimeAudioKey: return ("spatial-facetime-audio", "FaceTime Spatial Audio", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.responsiveShutterKey: return ("responsive-shutter", "Responsive Shutter", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.hypertensionNotifKey: return ("hypertension-notif", "Hypertension Notifications", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.appIntellKey: return ("ai-core-slot", "Apple Intelligence Core", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.photosCleanUpKey: return ("photos-cleanup-slot", "Photos Clean Up", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.handwritingSynthKey: return ("handwriting-slot", "Handwriting Synthesis", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.audioIntellKey: return ("audio-intell-slot", "iOS 27 Audio Intelligence", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.personalTranslatorKey: return ("personal-translator-slot", "Personal Translator", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.islandKey: return ("dynamic-island-slot", "Dynamic Island", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.aodKey: return ("aod-slot", "Always-On Display (AOD)", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.aoTimeKey: return ("aotime-slot", "Always-On Time", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.aodVibrancyKey: return ("aod-vibrancy-slot", "AOD Vibrancy", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.liquidGlassLowPowerKey: return ("liquid-glass-lp-slot", "Liquid Glass Low Power", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.chargeLimKey: return ("charge-limit-slot", "80% Charge Limit", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.bootChimeKey: return ("boot-chime-slot", "Boot Chime", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.crashDetKey: return ("crash-det-slot", "Crash Detection", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.pwmKey: return ("pwm-slot", "PWM Dimming", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.appPencilKey: return ("apple-pencil-slot", "Apple Pencil Support", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.camButtonKey: return ("cam-button-slot", "Camera Control Button", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.actButtonKey: return ("action-button-slot", "Action Button", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.tapToWakeKey: return ("tap-to-wake-slot", "Tap to Wake", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.stageMgrKey: return ("stage-mgr-slot", "Stage Manager", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.ipadModeKey: return ("ipad-mode-slot", "iPad Device Mode", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.medusaFloatingKey: return ("medusa-floating", "Medusa Floating Live App", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.medusaOverlayKey: return ("medusa-overlay", "Medusa Overlay App", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.medusaPinnedKey: return ("medusa-pinned", "Medusa Pinned App", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.medusaPipKey: return ("medusa-pip", "Medusa PIP", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.deviceClassNumberKey: return ("device-class-number", "DeviceClassNumber (1=iPhone, 3=iPad)", "3 (0x03 · iPad)", "1 (0x01 · iPhone)")
        case MGCacheDataLayout.shutterRelaxationKey: return ("shutter-relax-slot", "[Exp] Regional Shutter Relaxation", "true (0x01 · Mute Allowed)", "false (0x00 · Forced Shutter)")
        case MGCacheDataLayout.shutterKeyboardMutePreserveKey: return ("shutter-kb-mute-slot", "[Exp] Preserve Shutter (Keyboard Mute)", "true (0x01 · Force Preserved)", "false (0x00 · Force Removed)")
        case MGCacheDataLayout.shutterLegacyMutePreserveKey: return ("shutter-legacy-mute-slot", "[Exp] Preserve Shutter (Legacy)", "true (0x01 · Force Preserved)", "false (0x00 · Force Removed)")
        case MGCacheDataLayout.concurrentHPLPMicsKey: return ("concurrent-mics-slot", "[Exp] Concurrent HP/LP Mics", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.photosLocalLightKey: return ("photos-local-light-slot", "[Exp] Photos Local Light", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.toneMappingKey: return ("tone-mapping-slot", "[Exp] Tone Mapping", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.hdrDeferredProcessingKey: return ("hdr-deferred-slot", "[Exp] HDR Deferred Processing", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.spatialOverCaptureKey: return ("spatial-overcapture-slot", "[Exp] Spatial Over Capture", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.stereoAudioRecKey: return ("stereo-audio-rec-slot", "[Exp] Stereo Audio Recording", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.p3VideoRecKey: return ("p3-video-rec-slot", "[Exp] P3 Colorspace Video", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.touchSensitiveCamControlKey: return ("touch-cam-control-slot", "[Exp] Touch-Sensitive Camera Control", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.hardwareDetentsKey: return ("hw-detents-slot", "[Exp] Hardware Detents", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.cameraHapticsKey: return ("camera-haptics-slot", "[Exp] Camera Haptics", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.legacyBatteryInfoKey: return ("legacy-battery-info-slot", "[Exp] Legacy Battery Info", "true (0x01 · Show Cycles/Date)", "false (0x00 · Hidden)")
        case MGCacheDataLayout.legacyDynamicEndOfChargeKey: return ("legacy-dyn-eoc-slot", "[Exp] Legacy Dynamic End of Charge", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.highLuminanceAODKey: return ("high-lum-aod-slot", "[Exp] High Luminance AOD", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.aodFlipbookKey: return ("aod-flipbook-slot", "[Exp] AOD Flipbook", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.carPlay2Key: return ("carplay2-slot", "[Exp] CarPlay Ultra", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.touchDelivery120HzKey: return ("touch-120hz-slot", "[Exp] 120Hz Touch Delivery", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.hearingAidEQKey: return ("hearingaid-eq-slot", "[Exp] Hearing Aid EQ", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.hearingAidLEKey: return ("hearingaid-le-slot", "[Exp] Hearing Aid LE", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.hearingAidPowerRedKey: return ("hearingaid-pwr-slot", "[Exp] Hearing Aid Power Reduction", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.breathingDisturbancesKey: return ("sleep-apnea-slot", "[Exp] Breathing Disturbances", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.usBloodOxygenKey: return ("us-blood-oxygen-slot", "[Exp] US Blood Oxygen Limit", "true (0x01 · Patent Limited)", "false (0x00 · Unrestricted)")
        case MGCacheDataLayout.workoutUltraKey: return ("workout-ultra-slot", "[Exp] Workout Ultra Mode", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.timeInDaylightKey: return ("daylight-time-slot", "[Exp] Time in Daylight", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.siriHubKey: return ("siri-hub-slot", "[Exp] Siri Hub", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.onDeviceSiriKey: return ("ondevice-siri-slot", "[Exp] On-Device Siri", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        case MGCacheDataLayout.modelPruningKey: return ("model-pruning-slot", "[Exp] Model Pruning", "true (0x01 · Enabled)", "false (0x00 · Disabled)")
        default: return (key, "Hardware Feature Slot (\(key))", "true (0x01)", "false (0x00)")
        }
    }

    func diffDetails(from beforeDict: NSDictionary, to afterDict: NSDictionary, using customLayout: MGCacheDataLayout? = nil) -> [MGCacheDataDiffDetail] {
        guard let beforeData = beforeDict["CacheData"] as? Data,
              let afterData = afterDict["CacheData"] as? Data,
              beforeData != afterData,
              beforeData.count == afterData.count else { return [] }

        let resolvedLayout: MGCacheDataLayout? = customLayout ?? {
            if case .success(let l) = libraryLayout() { return l }
            return nil
        }()

        guard let layout = resolvedLayout,
              case .success = layout.validatePlist(beforeDict),
              case .success = layout.validatePlist(afterDict) else { return [] }

        var details: [MGCacheDataDiffDetail] = []
        var describedOffsets = Set<Int>()

        let slots: [(id: String, label: String, key: String, slot: Int, trueHint: String, falseHint: String)] = {
            var arr: [(String, String, String, Int, String, String)] = [
                ("green-tea", "CN Restriction Flag (green-tea)", MGCacheDataLayout.greenTeaKey, layout.greenTeaIndex, "true (0x01 · Restricted)", "false (0x00 · Unlocked)"),
                ("not-green-tea", "Non-CN Device Flag (not-green-tea)", MGCacheDataLayout.notGreenTeaKey, layout.notGreenTeaIndex, "true (0x01 · Non-CN)", "false (0x00 · CN Default)")
            ]
            if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: beforeData) && layout.validateSingleBooleanSlot(wIdx, in: afterData) {
                arr.append(("wapi", "WLAN Display Flag (wapi)", MGCacheDataLayout.wapiKey, wIdx, "true (0x01 · WLAN)", "false (0x00 · Wi-Fi)"))
            }
            for fKey in layout.featureSlotIndices.keys.sorted() {
                if let fSlot = layout.featureSlotIndices[fKey],
                   layout.validateSingleBooleanSlot(fSlot, in: beforeData),
                   layout.validateSingleBooleanSlot(fSlot, in: afterData) {
                    let meta = Self.featureSlotMeta(forKey: fKey)
                    arr.append((meta.id, meta.label, fKey, fSlot, meta.trueHint, meta.falseHint))
                }
            }
            return arr
        }()

        for entry in slots {
            let off = entry.slot * 8
            if beforeData[off] != afterData[off] {
                describedOffsets.insert(off)
                details.append(
                    MGCacheDataDiffDetail(
                        id: "CacheData.\(entry.id)",
                        label: entry.label,
                        keyPath: String(format: "CacheData[0x%X] · Slot %d (%@)".loc, off, entry.slot, entry.key),
                        beforeText: beforeData[off] != 0 ? entry.trueHint : entry.falseHint,
                        afterText: afterData[off] != 0 ? entry.trueHint : entry.falseHint
                    )
                )
            }
        }

        let otherChangedCount = beforeData.indices.filter { !describedOffsets.contains($0) && beforeData[$0] != afterData[$0] }.count
        if otherChangedCount > 0 {
            details.append(
                MGCacheDataDiffDetail(
                    id: "CacheData.other",
                    label: "Other Binary Cache Offsets",
                    keyPath: "CacheData",
                    beforeText: "<Data: \(beforeData.count) bytes>",
                    afterText: "<Changed \(otherChangedCount) bytes>"
                )
            )
        }
        return details
    }

    func diagnosticReport(for dict: NSDictionary) -> String {
        switch resolveValidated(for: dict) {
        case .failure(let err):
            return "Status: ❌ Dynamic resolution failed (Modification denied and locked)\nReason: \(err.localizedDescription)"
        case .success((let layout, let data)):
            let gtVal = data[layout.greenTeaOffset] == 1
            let ngtVal = data[layout.notGreenTeaOffset] == 1
            var lines: [String] = [
                "Status: ✅ Exactly matched system library and cache file",
                "CacheUUID: \(layout.uuid)",
                "Total slots: \(layout.slotCount) (\(layout.byteCount) bytes)",
                String(format: "green-tea: Slot %d, Offset 0x%X (Validity 0x%X), Current = %@".loc,
                       layout.greenTeaIndex, layout.greenTeaOffset, layout.validityOffset(for: layout.greenTeaIndex), gtVal ? "true" : "false"),
                String(format: "not-green-tea: Slot %d, Offset 0x%X (Validity 0x%X), Current = %@".loc,
                       layout.notGreenTeaIndex, layout.notGreenTeaOffset, layout.validityOffset(for: layout.notGreenTeaIndex), ngtVal ? "true" : "false")
            ]
            if let wIdx = layout.wapiIndex, layout.validateSingleBooleanSlot(wIdx, in: data) {
                let wOff = wIdx * 8
                let wVal = data[wOff] == 1
                lines.append(String(format: "wapi (WLAN/Wi-Fi): Slot %d, Offset 0x%X (Validity 0x%X), Current = %@".loc,
                                    wIdx, wOff, layout.validityOffset(for: wIdx), wVal ? "true (WLAN)" : "false (Wi-Fi)"))
            } else {
                lines.append("wapi (WLAN/Wi-Fi): No valid slot resolved on current system (Disabled)")
            }
            for fKey in MGCacheDataLayout.mediaHealthSlotKeys.sorted() {
                if let fSlot = layout.featureSlotIndices[fKey], layout.validateSingleBooleanSlot(fSlot, in: data) {
                    let meta = Self.featureSlotMeta(forKey: fKey)
                    let fVal = data[fSlot * 8] == 1
                    lines.append(String(format: "%@: Slot %d, Offset 0x%X, Current = %@".loc,
                                        meta.label, fSlot, fSlot * 8, fVal ? "true" : "false"))
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}