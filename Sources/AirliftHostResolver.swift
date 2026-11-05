import Foundation

enum AirliftHostResolver {
    static func bestAvailable(log: (String) -> Void) async -> String? {
        log("Đang quét interface mạng để tìm RSD Tunnel...")
        
        var ipv4Candidate: String?
        var ipv6Candidate: String?
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            
            let family = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)
            
            // Tìm interface VPN (utun)
            if name.hasPrefix("utun") {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                
                // Check IPv4
                if family == UInt8(AF_INET) {
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || ip.hasPrefix("172.") {
                        ipv4Candidate = ip
                    }
                }
                // Check IPv6
                else if family == UInt8(AF_INET6) {
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    // Địa chỉ IPv6 nội bộ của tunnel thường có dạng fd00:: hoặc fe80::
                    if ip.hasPrefix("fd") || ip.hasPrefix("fe80") {
                        ipv6Candidate = ip
                    }
                }
            }
        }
        
        // Ưu tiên IPv6 (iOS 17+ thường dùng cái này cho RSD)
        if let v6 = ipv6Candidate {
            log("✅ Tìm thấy Tunnel (IPv6): \(v6)")
            return v6
        }
        if let v4 = ipv4Candidate {
            log("✅ Tìm thấy Tunnel (IPv4): \(v4)")
            return v4
        }
        
        // Nếu không tìm thấy, fallback về IP mặc định của StikDebug/SideStore
        log("⚠️ Không tìm thấy interface utun. Thử dùng IP mặc định 10.7.0.1...")
        return "10.7.0.1"
    }
}