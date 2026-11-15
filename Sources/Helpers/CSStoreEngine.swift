import Foundation

class CSStoreEngine {
    static let shared = CSStoreEngine()
    private init() {}

    static func normalizeVarPath(_ path: String) -> String {
        if path == "/private/var" { return "/var" }
        if path.hasPrefix("/private/var/") {
            return "/var/" + path.dropFirst("/private/var/".count)
        }
        return path
    }

    private static let launchServicesMapPath = "/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist"
    private static let appContainerRoot = "/var/mobile/Containers/Data/Application"

    private var cachedBundleMap: [String: String]?
    private var cacheTimestamp: Date?
    private let cacheLock = NSLock()
    private let cacheTTL: TimeInterval = 30

    private func loadBundleMap() -> [String: String]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cachedBundleMap, let ts = cacheTimestamp, Date().timeIntervalSince(ts) < cacheTTL {
            return cached
        }

        guard let data = FileManager.default.contents(atPath: Self.launchServicesMapPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let user = plist["User"] as? [String: Any] else {
            return nil
        }

        var map: [String: String] = [:]
        for (bundleID, value) in user {
            guard let dict = value as? [String: Any], let containerUUID = dict["Container"] as? String, !containerUUID.isEmpty else { continue }
            map[bundleID] = "\(Self.appContainerRoot)/\(containerUUID)"
        }

        cachedBundleMap = map
        cacheTimestamp = Date()
        return map
    }

    func lookupAppContainer(forBundleID bundleID: String) -> (Bool, String?) {
        guard let map = loadBundleMap() else { return (false, nil) }
        return (true, map[bundleID])
    }

    func containerPaths(forRoot root: String) -> [String]? {
        let normalizedRoot = CSStoreEngine.normalizeVarPath(root)
        guard normalizedRoot == Self.appContainerRoot else { return nil }
        guard let map = loadBundleMap(), !map.isEmpty else { return nil }
        return Array(map.values)
    }
}
