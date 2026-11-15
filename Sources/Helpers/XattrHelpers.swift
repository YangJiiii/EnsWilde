import Foundation

private var _xattrBIDCache: [String: String] = [:]
private let _xattrBIDCacheLock = NSLock()

func clearXattrBIDCache() {
    _xattrBIDCacheLock.lock()
    _xattrBIDCache.removeAll(keepingCapacity: true)
    _xattrBIDCacheLock.unlock()
}

func getBIDFromXattr(_ url: URL) -> String? {
    let path = url.path

    _xattrBIDCacheLock.lock()
    if let cached = _xattrBIDCache[path] {
        _xattrBIDCacheLock.unlock()
        return cached
    }
    _xattrBIDCacheLock.unlock()

    let candidates = [
        "com.apple.containermanagerd.metadata.bundle-identifier",
        "com.apple.containermanagerd.metadata.plist"
    ]

    for attrName in candidates {
        let length = getxattr(path, attrName, nil, 0, 0, 0)
        guard length > 0, length < 4096 else { continue }
        var buffer = [UInt8](repeating: 0, count: length)
        let read = getxattr(path, attrName, &buffer, length, 0, 0)
        guard read > 0 else { continue }

        if attrName.hasSuffix(".plist") {
            let data = Data(buffer.prefix(read))
            if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let bid = (dict["MCMMetadataIdentifier"] as? String) ?? (dict["Identifier"] as? String),
               !bid.isEmpty {
                _xattrBIDCacheLock.lock()
                _xattrBIDCache[path] = bid
                _xattrBIDCacheLock.unlock()
                return bid
            }
        } else {
            let bid = String(decoding: buffer.prefix(read), as: UTF8.self)
                .trimmingCharacters(in: .controlCharacters)
            if !bid.isEmpty {
                _xattrBIDCacheLock.lock()
                _xattrBIDCache[path] = bid
                _xattrBIDCacheLock.unlock()
                return bid
            }
        }
    }
    return nil
}
