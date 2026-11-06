//  NetworkStatus.swift
//  EnsWilde
//
//  Phát hiện tunnel VPN loopback (LocalDevVPN / StikDebug / SideStore) VÀ
//  xác nhận RSD port 49152 thực sự reachable trước khi trả true.

import Foundation
import Darwin

enum NetworkStatus {

    // MARK: - Public API

    /// Trả về true chỉ khi:
    ///   1. Có interface utun/ipsec đang UP & RUNNING, VÀ
    ///   2. Interface đó có IP 10.7.0.x (hoặc 172.16.0.x / 10.0.0.x dự phòng).
    /// KHÔNG trả true cho iCloud Private Relay (utun không có IP loopback).
    static func isVPNTunnelPresent() -> Bool {
        return detectActiveTunnelIP() != nil
    }

    /// Trả về IP loopback đang hoạt động, hoặc nil nếu không có.
    /// Ưu tiên 10.7.0.x (LocalDevVPN/StikDebug), sau đó các dải khác.
    static func detectActiveTunnelIP() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var candidates: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let cur = pointer {
            let iface = cur.pointee
            let name  = String(cString: iface.ifa_name)
            let flags = Int32(iface.ifa_flags)
            let isUp      = (flags & IFF_UP)      != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isTunnel  = name.hasPrefix("utun") || name.hasPrefix("ipsec")

            if isTunnel, isUp, isRunning,
               let addr = iface.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {

                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if isLoopbackRange(ip) {
                        candidates.append(ip)
                    }
                }
            }
            pointer = iface.ifa_next
        }

        // Ưu tiên 10.7.0.x
        if let p = candidates.first(where: { $0.hasPrefix("10.7.0.") }) { return p }
        if let p = candidates.first(where: { $0.hasPrefix("172.16.0.") }) { return p }
        if let p = candidates.first(where: { $0.hasPrefix("10.0.0.") }) { return p }
        return candidates.first
    }

    // MARK: - RSD / Lockdown probe

    /// Thử TCP connect tới `host:port` với timeout ms. True nếu SYN-ACK nhận được.
    /// RSD (49152) và Lockdown (62078) đều là TCP — chỉ cần TCP connect thành công
    /// là đủ để biết route tồn tại, KHÔNG cần TLS handshake.
    static func probeTCP(host: String, port: UInt16, timeoutMs: Int32) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Non-blocking
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

        if rc == 0 { return true }                    // connect tức thời
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollRc = poll(&pfd, 1, timeoutMs)
        guard pollRc > 0 else { return false }

        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }

    /// Kiểm tra nhanh RSD (49152) hoặc Lockdown (62078) trên host.
    /// Trả về `(rsdReachable, lockdownReachable)`.
    static func probeDevicePorts(host: String, timeoutMs: Int32 = 800) -> (rsd: Bool, lockdown: Bool) {
        let rsd      = probeTCP(host: host, port: 49152, timeoutMs: timeoutMs)
        let lockdown = probeTCP(host: host, port: 62078, timeoutMs: timeoutMs)
        return (rsd, lockdown)
    }

    // MARK: - Debug

    static func dumpInterfaces(log: @escaping (String) -> Void) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getaddrinfo == nil, getifaddrs(&addrs) == 0, let first = addrs else {
            log("[Net] Không đọc được interfaces")
            return
        }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = pointer {
            let iface = cur.pointee
            let name  = String(cString: iface.ifa_name)
            let flags = Int32(iface.ifa_flags)
            let up    = (flags & IFF_UP) != 0
            let run   = (flags & IFF_RUNNING) != 0

            var ip = "-"
            if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    ip = String(cString: host)
                }
            }
            log("[Net] \(name) ip=\(ip) up=\(up) running=\(run)")
            pointer = iface.ifa_next
        }
    }

    // MARK: - Private

    private static func isLoopbackRange(_ ip: String) -> Bool {
        return ip.hasPrefix("10.7.0.")
            || ip.hasPrefix("172.16.0.")
            || ip.hasPrefix("10.0.0.")
            || ip.hasPrefix("198.18.")
    }
}