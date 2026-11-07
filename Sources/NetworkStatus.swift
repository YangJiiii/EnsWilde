//  NetworkStatus.swift
//  EnsWilde
//
//  Sửa: Chấp nhận mọi IP 10.7.x.x và bỏ check IFF_RUNNING để tránh false negative.

import Foundation
import Darwin

enum NetworkStatus {

    static func isVPNTunnelPresent() -> Bool {
        return detectActiveTunnelIP() != nil
    }

    /// Trả về IP loopback đang hoạt động, hoặc nil nếu không có.
    static func detectActiveTunnelIP() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let cur = pointer {
            let iface = cur.pointee
            let name  = String(cString: iface.ifa_name)
            let flags = Int32(iface.ifa_flags)
            let isUp  = (flags & IFF_UP) != 0
            
            // Chỉ cần UP, không cần RUNNING (tránh false negative trên iOS 17+)
            let isTunnel  = name.hasPrefix("utun") || name.hasPrefix("ipsec")

            if isTunnel, isUp,
               let addr = iface.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {

                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    // Chấp nhận 10.7.x.x (bao gồm cả 10.7.1.1 của LocalDevVPN)
                    if ip.hasPrefix("10.7.") || ip.hasPrefix("172.16.") || ip.hasPrefix("10.0.0.") {
                        return ip
                    }
                }
            }
            pointer = iface.ifa_next
        }
        return nil
    }

    // MARK: - RSD / Lockdown probe

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
            
            var ip = "-"
            if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    ip = String(cString: host)
                }
            }
            log("[Net] \(name) ip=\(ip) up=\(up)")
            pointer = iface.ifa_next
        }
    }
}