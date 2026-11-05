import Foundation

enum AirliftHostResolver {
    static func bestAvailable(log: (String) -> Void) async -> String? {
        log("Đang kiểm tra kết nối RSD Tunnel...")
        
        var ipv4Candidate: String?
        var ipv6Candidate: String?
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            log("⚠️ Không thể lấy danh sách interface mạng. Thử IP mặc định.")
            return "10.7.0.1"
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            
            let family = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)
            
            if name.hasPrefix("utun") {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                
                if family == UInt8(AF_INET) {
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && ip != "127.0.0.1" {
                        ipv4Candidate = ip
                    }
                } else if family == UInt8(AF_INET6) {
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    var ip = String(cString: hostname)
                    if let percentIndex = ip.firstIndex(of: "%") {
                        ip = String(ip[..<percentIndex])
                    }
                    if !ip.isEmpty && ip != "::1" {
                        ipv6Candidate = ip
                    }
                }
            }
        }
        
        // Ưu tiên IPv6
        if let v6 = ipv6Candidate {
            log("✅ Tìm thấy Tunnel (IPv6): \(v6)")
            return v6
        }
        
        if let v4 = ipv4Candidate {
            log("✅ Tìm thấy Tunnel (IPv4): \(v4)")
            return v4
        }
        
        // Fallback nếu không tìm thấy
        log("⚠️ Không tìm thấy interface utun. Thử dùng IP mặc định 10.7.0.1")
        return "10.7.0.1"
    }
}