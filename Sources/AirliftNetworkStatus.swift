//  AirliftNetworkStatus.swift
//  EnsWilde
//
//  Kiểm tra VPN loopback (LocalDevVPN / SideStore) đã bật chưa.
//  Airlift cần interface utun để tự dial 10.7.0.1:49152 (RSD) và :62078 (Lockdown).

import Foundation

enum AirliftNetworkStatus {

    /// Trả về true nếu có ít nhất một tunnel interface (utun/ipsec) đang hoạt động.
    static func isVPNTunnelPresent() -> Bool {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return false
        }
        defer { freeifaddrs(ifaddrPtr) }

        var found = false
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let name = String(cString: ptr.pointee.ifa_name)

            // utun* là các tunnel do NetworkExtension tạo ra (LocalDevVPN, WireGuard, SideStore).
            // ipsec* dùng cho VPN kiểu IKEv2.
            if isUp && !isLoopback && (name.hasPrefix("utun") || name.hasPrefix("ipsec")) {
                found = true
                break
            }
        }
        return found
    }

    /// Kiểm tra VPN và ném lỗi nếu chưa bật.
    static func requireVPN() throws {
        guard isVPNTunnelPresent() else {
            throw AirliftError.vpnNotEnabled
        }
    }

    /// In danh sách interface ra log (debug).
    static func dumpInterfaces(log: (String) -> Void) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            log("[Net] Không đọc được interfaces")
            return
        }
        defer { freeifaddrs(ifaddrPtr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            let flags = Int32(ptr.pointee.ifa_flags)
            let up = (flags & IFF_UP) != 0
            log("[Net] \(name) up=\(up)")
        }
    }
}

// MARK: - Errors

enum AirliftError: LocalizedError {
    case vpnNotEnabled
    case pairingFileMissing(String)
    case ffiFailure(code: Int32, message: String)
    case sourceDirectoryMissing(String)

    var errorDescription: String? {
        switch self {
        case .vpnNotEnabled:
            return "VPN chưa bật. Hãy mở LocalDevVPN/SideStore và bật tunnel trước khi chạy."
        case .pairingFileMissing(let p):
            return "Không tìm thấy pairing file tại \(p). Hãy Pair thiết bị trước."
        case .ffiFailure(let code, let msg):
            return "Airlift FFI lỗi (\(code)): \(msg)"
        case .sourceDirectoryMissing(let p):
            return "Thư mục nguồn không tồn tại: \(p)"
        }
    }
}
