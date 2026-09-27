//
//  Utils.swift
//  EnsWilde
//

import Foundation
import UIKit

final class Utils {
    static let os = ProcessInfo().operatingSystemVersion
    static var udid = "0000-000000000000"
    static var port: UInt16 = 0
    static var bgTask: UIBackgroundTaskIdentifier = .invalid

    static func buildToUInt64(_ build: String) -> UInt64 {
        let bytes = Array(build.utf8)
        var value: UInt64 = 0
        for i in 0..<min(bytes.count, 8) {
            value = (value << 8) | UInt64(bytes[i])
        }
        for _ in bytes.count..<8 {
            value = (value << 8) | 0x7F
        }
        return value
    }

    static func requiresVersion(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) -> Bool {
        let requiredVersion = major * 10000 + minor * 100 + patch
        let currentVersion = os.majorVersion * 10000 + os.minorVersion * 100 + os.patchVersion
        return currentVersion < requiredVersion
    }
    
    /// Check if iOS version is supported (iOS 18.0+)
static func isIOSVersionSupported() -> Bool {
    let currentVersion = os.majorVersion * 10000
        + os.minorVersion * 100
        + os.patchVersion

    let minVersion = 18 * 10000

    return currentVersion >= minVersion
}
    
    /// Get current iOS version string (e.g., "18.1" or "18.1.2")
    static func getIOSVersionString() -> String {
        if os.patchVersion == 0 {
            return "\(os.majorVersion).\(os.minorVersion)"
        }
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    // MARK: - HTTP server readiness

    static func ensureHTTPServerReady(timeoutSeconds: Double = 5.0) async throws -> UInt16 {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Utils.port == 0 {
            if Date() >= deadline {
                throw NSError(
                    domain: "Utils",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP server not ready (port not assigned). Reopen the app and try again."]
                )
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return Utils.port
    }

    static func verifyLocalHTTPFileAccessible(pathComponent: String, timeoutSeconds: Double = 3.0) async throws {
        let port = try await ensureHTTPServerReady(timeoutSeconds: timeoutSeconds)
        guard let url = URL(string: "http://localhost:\(port)/\(pathComponent)") else {
            throw NSError(domain: "Utils", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Invalid localhost URL"])
        }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = timeoutSeconds

        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            throw NSError(domain: "Utils", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Local HTTP did not serve \(pathComponent) (status \(code))"])
        }
    }

    // MARK: - Port reserve

    static func reservePort() throws -> UInt16 {
        let serverSock = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSock >= 0 else { throw ServerError.cannotReservePort }
        defer { close(serverSock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = 0

        var len = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let res = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                let res1 = bind(serverSock, $0, len)
                let res2 = getsockname(serverSock, $0, &len)
                return (res1, res2)
            }
        }
        guard res.0 == 0 && res.1 == 0 else { throw ServerError.cannotReservePort }
        guard listen(serverSock, 1) == 0 else { throw ServerError.cannotReservePort }

        let clientSock = socket(AF_INET, SOCK_STREAM, 0)
        guard clientSock >= 0 else { throw ServerError.cannotReservePort }
        defer { close(clientSock) }

        let res3 = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(clientSock, $0, len)
            }
        }
        guard res3 == 0 else { throw ServerError.cannotReservePort }

        let acceptSock = accept(serverSock, nil, nil)
        guard acceptSock >= 0 else { throw ServerError.cannotReservePort }
        defer { close(acceptSock) }

        return addr.sin_port.byteSwapped
    }

    enum ServerError: Error { case cannotReservePort }
}
