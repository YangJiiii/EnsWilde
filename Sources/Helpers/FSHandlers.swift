//
//  FSHandlers.swift
//  Erosion
//
//  Created by lunginspector on 8/19/26.
//

import Foundation
import UIKit

private let fm = FileManager.default

let fsHandlers = FSHandlers()

class FSHandlers {
    private let cacheLock = NSLock()
    private let scanSerialLock = NSLock()
    private var dirPathsCache: [String: [String]] = [:]

    func invalidateCache() {
        cacheLock.lock()
        dirPathsCache.removeAll()
        cacheLock.unlock()
        clearXattrBIDCache()
    }

    func getDirPaths(_ path: String, maxInode: Int64 = 15000000, forceRefresh: Bool = false) -> [String] {
        let normKey = CSStoreEngine.normalizeVarPath(path)

        if !forceRefresh {
            cacheLock.lock()
            if let cached = dirPathsCache[normKey], !cached.isEmpty {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
        }

        // Single-flight: prevent 5 concurrent views from launching 5 parallel pathleak loops!
        scanSerialLock.lock()
        defer { scanSerialLock.unlock() }

        if !forceRefresh {
            cacheLock.lock()
            if let cached = dirPathsCache[normKey], !cached.isEmpty {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()
        }

        // [测试特性] Try MCM / LaunchServices CSStore2 fast container graph (<50ms) first
        if let fastPaths = CSStoreEngine.shared.containerPaths(forRoot: normKey), fastPaths.count >= 2 {
            print(L("(fs) 已通过 CSStore2 极速映射获取 \(normKey) 下 \(fastPaths.count) 个容器路径"))
            cacheLock.lock()
            dirPathsCache[normKey] = fastPaths
            cacheLock.unlock()
            return fastPaths
        }

        let baselineURL = fm.temporaryDirectory.appendingPathComponent(".baseline_\(UUID().uuidString)")
        var baselineInode: UInt64 = 0

        do {
            try "baseline".write(to: baselineURL, atomically: true, encoding: .utf8)
            var baselineInfo = stat()
            if stat(baselineURL.path, &baselineInfo) == 0 {
                baselineInode = baselineInfo.st_ino
                print(L("(fs) 动态探测本机当前最大 Inode 基线: \(baselineInode)"))
            }
            try? fm.removeItem(at: baselineURL)
        } catch {
            print(L("(fs) 获取动态 Inode 基线失败，回退至预设上限: \(error.localizedDescription)"))
        }

        let userMax = UInt64(max(maxInode, 1_000_000))
        let targetMaxInode: UInt64
        if baselineInode > 0 {
            // Respect userMax (default 15,000,000) so long-used devices with 200M+ cumulative APFS inodes
            // do not hang for 5–6 minutes scanning 0..baselineInode, while still stopping early on fresh devices.
            targetMaxInode = min(baselineInode + 50_000, userMax)
        } else {
            targetMaxInode = userMax
        }
        print(L("(fs) 正在通过多线程 pathleak 枚举目录: \(normKey) (扫描上限: \(targetMaxInode), 本机最大 Inode: \(baselineInode))"))
        let leakedPaths: [String] = (pathleak(normKey, targetMaxInode) as? [String]) ?? []
        print(L("(fs) pathleak 枚举完成，共找到 \(leakedPaths.count) 个容器路径"))
        if !leakedPaths.isEmpty {
            cacheLock.lock()
            dirPathsCache[normKey] = leakedPaths
            cacheLock.unlock()
        }
        return leakedPaths
    }
    
    func getContainerPath(at containerURL: URL = FSURL.appContainers, forMatch match: String, hashOnly: Bool = false) -> String {
        let normRoot = CSStoreEngine.normalizeVarPath(containerURL.path)
        if normRoot == "/var/mobile/Containers/Data/Application" {
            let (snapLoaded, fastHit) = CSStoreEngine.shared.lookupAppContainer(forBundleID: match)
            if let fastHit, !fastHit.isEmpty {
                let url = URL(fileURLWithPath: fastHit)
                return hashOnly ? url.lastPathComponent : url.path
            }
            // If CSStore2 is active and did not list this app, it is uninstalled/not initialized — do not brute-force!
            if snapLoaded {
                return ""
            }
        }

        let containers = getDirPaths(containerURL.path)
        for path in containers {
            let url = URL(fileURLWithPath: path)
            if let appName = getBIDFromXattr(url) {
                if appName.caseInsensitiveCompare(match) == .orderedSame {
                    if hashOnly {
                        return url.lastPathComponent
                    }
                    return url.path
                }
            }
        }
        print("(fs) failed to get container for \(match)! containers: \(containerURL.path)")
        return ""
    }
    
    func openInFilesApp(_ fileURL: URL) {
        guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "shareddocuments"
        guard let filesAppURL = components.url else { return }
        UIApplication.shared.open(filesAppURL)
    }
}