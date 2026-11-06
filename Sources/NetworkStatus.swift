//  NetworkStatus.swift
//  EnsWilde
//
//  Kiểm tra VPN loopback (LocalDevVPN / StikDebug / SideStore).
//  Airlift cần interface utun để dial RSD 49152 và fallback Lockdown 62078.

import Foundation
import Network

enum NetworkStatus {

    static func checkVPNStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let active = isVPNTunnelPresent()
            DispatchQueue.main.async { completion(active) }
        }
    }

    /// Trả về true nếu có ít nhất một tunnel interface đang hoạt động.
    static func isVPNTunnelPresent() -> Bool {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            return false
        }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING

            // 1. Kiểm tra IP loopback đặc trưng của các VPN phổ biến
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if ip.hasPrefix("10.7.0.") || ip.hasPrefix("198.18.0.") {
                    return true
                }
            }

            // 2. Nếu không khớp IP, kiểm tra tên interface VPN đang UP & RUNNING
            let isVPNInterface = name.hasPrefix("utun")
                || name.hasPrefix("ipsec")
                || name.hasPrefix("tap")
                || name.hasPrefix("ppp")
            if isVPNInterface && isUp && isRunning {
                return true
            }

            pointer = interface.ifa_next
        }
        return false
    }

    /// Log danh sách interface để debug khi cần.
    static func dumpInterfaces(log: @escaping (String) -> Void) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let firstAddr = addrs else {
            log("[Net] Không đọc được interfaces")
            return
        }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            let name = String(cString: current.pointee.ifa_name)
            let flags = Int32(current.pointee.ifa_flags)
            let up = (flags & IFF_UP) == IFF_UP
            log("[Net] \(name) up=\(up)")
            pointer = current.pointee.ifa_next
        }
    }
}