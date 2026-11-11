//  NetworkStatus.swift
//  EnsWilde
//
//  Nhận diện động mọi IP của tunnel (utun/ipsec/tap/ppp), bao gồm cả
//  Tunnel IP (ifa_addr) và Device/Peer IP (ifa_dstaddr).
//  Dùng TCP probe để xác nhận IP nào thực sự route tới RSD 49152.

import Foundation
import Darwin

enum NetworkStatus {

    // MARK: - Public API

    static func isVPNTunnelPresent() -> Bool {
        return !detectAllTunnelIPs().isEmpty
    }

    /// Trả về IP đầu tiên tìm thấy (tương thích ngược).
    static func detectActiveTunnelIP() -> String? {
        return detectAllTunnelIPs().first
    }

    /// Quét TẤT CẢ các tunnel interface đang UP và trả về mọi IP IPv4
    /// tìm thấy, bao gồm cả `ifa_addr` (Tunnel IP) và `ifa_dstaddr` (Device IP).
    static func detectAllTunnelIPs() -> [String] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return [] }
        defer { freeifaddrs(addrs) }

        var ips = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let cur = pointer {
            let iface = cur.pointee
            let name  = String(cString: iface.ifa_name)
            let flags = Int32(iface.ifa_flags)
            let isUp  = (flags & IFF_UP) != 0

            let isTunnel = name.hasPrefix("utun")
                || name.hasPrefix("ipsec")
                || name.hasPrefix("tap")
                || name.hasPrefix("ppp")

            if isTunnel && isUp {
                // 1. Tunnel IP (phía ta)
                if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    if let ip = ipString(from: addr), isValidLoopback(ip) {
                        ips.insert(ip)
                    }
                }
                // 2. Device/Peer IP (phía bên kia của point-to-point tunnel)
                if let dst = iface.ifa_dstaddr, dst.pointee.sa_family == UInt8(AF_INET) {
                    if let ip = ipString(from: dst), isValidLoopback(ip) {
                        ips.insert(ip)
                    }
                }
            }
            pointer = iface.ifa_next
        }
        return Array(ips).sorted()
    }

    // MARK: - TCP probe

    /// Thử TCP connect tới `host:port` với timeout ms.
    static func probeTCP(host: String, port: UInt16, timeoutMs: Int32) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let rc = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollRc = poll(&pfd, 1, timeoutMs)
        guard pollRc > 0 else { return false }

        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }

    static func probeDevicePorts(host: String, timeoutMs: Int32 = 800) -> (rsd: Bool, lockdown: Bool) {
        let rsd      = probeTCP(host: host, port: 49152, timeoutMs: timeoutMs)
        let lockdown = probeTCP(host: host, port: 62078, timeoutMs: timeoutMs)
        return (rsd, lockdown)
    }

    // MARK: - Debug

    static func dumpInterfaces(log: @escaping (String) -> Void) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = pointer {
            let iface = cur.pointee
            let name  = String(cString: iface.ifa_name)
            let flags = Int32(iface.ifa_flags)
            let up    = (flags & IFF_UP) != 0

            var addrStr = "-"
            if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                addrStr = ipString(from: addr) ?? "-"
            }
            var dstStr = "-"
            if let dst = iface.ifa_dstaddr, dst.pointee.sa_family == UInt8(AF_INET) {
                dstStr = ipString(from: dst) ?? "-"
            }

            log("[Net] \(name) up=\(up) addr=\(addrStr) dst=\(dstStr)")
            pointer = iface.ifa_next
        }
    }

    // MARK: - Helpers

    private static func ipString(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                       &host, socklen_t(host.count),
                       nil, 0, NI_NUMERICHOST) == 0 {
            return String(cString: host)
        }
        return nil
    }

    /// Chỉ chấp nhận các dải IP loopback/private thường dùng cho tunnel.
    private static func isValidLoopback(_ ip: String) -> Bool {
        return ip.hasPrefix("10.")
            || ip.hasPrefix("172.16.")
            || ip.hasPrefix("192.168.")
            || ip.hasPrefix("198.18.")
    }
}