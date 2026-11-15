//
//  DeviceInfoHelpers.swift
//  Erosion
//
//  Created by lunginspector on 8/14/26.
//

import Foundation

import UIKit

let vrs = ProcessInfo.processInfo.operatingSystemVersion
// rave is the internal codename for ios 27
func raveSupported() -> Bool {
    // Skadz 2026-11-08:
    //   we're updating to worse_query which is at the moment a 0day
    //   add back in and update whenever it gets patched ig
    return vrs.majorVersion >= 27
}

func isSupported() -> Bool {
    // Skadz 2026-11-08:
    //   we're updating to worse_query which is at the moment a 0day
    //   add back in and update whenever it gets patched ig
    return true
    
//    if (vrs.majorVersion == 26 && vrs.minorVersion < 7) || raveSupported() {
//        return true
//    }
//    return false
}

func doubleSysVrs() -> Double {
    let pieces = [String(vrs.majorVersion), String(vrs.minorVersion)]
    let combined = pieces.joined(separator: ".")
    return Double(combined) ?? 0.0
}



// device info getters
func machineName() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    return machineMirror.children.reduce("") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return identifier }
        return identifier + String(UnicodeScalar(UInt8(value)))
    }
}

func buildNumber() -> String {
    var versString = [CChar](repeating: 0, count: 16)
    var versStringLen = size_t(versString.count - 1)
    let res = sysctlbyname("kern.osversion", &versString, &versStringLen, nil, 0)
    if res == 0, let buildNum = String(validatingUTF8: versString) {
        return buildNum
    }
    return L("未知")
}

func isPad() -> Bool {
    return UIDevice.current.userInterfaceIdiom == .pad
}
