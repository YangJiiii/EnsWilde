import Foundation
import Network
import AirliftFFI

private var airliftLogSink: ((String) -> Void)?

private let airliftLogCallback: ALLogCallback = { (ctx, msg) in
    guard let msg = msg else { return }
    let line = String(cString: msg)
    airliftLogSink?(line)
}

enum AirliftHostResolver {
    
    // Tập hợp tất cả các IP khả thi cho LocalDevVPN 1.3.0
    static func candidates() -> [String] {
        var out: [String] = []
        
        // 1. Lấy từ cài đặt thủ công (nếu người dùng đã override)
        if let override = UserDefaults.standard.string(forKey: "TunnelDeviceIP"), !override.isEmpty {
            out.append(override)
        }
        
        // 2. Tự động quét tất cả interface mạng (utun) để lấy IP thực tế đang được cấp
        if let detected = detectFromInterfaces() {
            for ip in detected where !out.contains(ip) {
                out.append(ip)
            }
        }
        
        // 3. Bổ sung danh sách IP mặc định của LocalDevVPN 1.3.0 và các tool khác
        let commonIPs = [
            "10.7.0.1",       // Peer IP mặc định (đích kết nối cũ)
            "10.7.1.1",       // Interface IP mới (LocalDevVPN 1.3.0)
            "10.7.0.2",       // Dải dự phòng
            "10.7.1.2",
            "127.0.0.1",      // Loopback
            "172.16.0.1",     // StikDebug / WireGuard
            "198.18.0.1"      // SideStore
        ]
        
        for ip in commonIPs where !out.contains(ip) {
            out.append(ip)
        }
        
        return out
    }
    
    // Quét tất cả interface utun (cả IPv4 và IPv6)
    static func detectFromInterfaces() -> [String]? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        
        var foundIPs: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr else { continue }
            
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            
            let name = String(cString: cur.pointee.ifa_name)
            // Chỉ lấy IP từ các interface VPN thực sự
            if name.hasPrefix("utun") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                
                if !ip.isEmpty && ip != "0.0.0.0" && ip != "127.0.0.1" && !ip.hasPrefix("fe80") {
                    let cleanIP = ip.components(separatedBy: "%").first ?? ip
                    if !foundIPs.contains(cleanIP) {
                        foundIPs.append(cleanIP)
                    }
                }
            }
        }
        return foundIPs.isEmpty ? nil : foundIPs
    }
    
    // Tìm IP tốt nhất: thử cả cổng RSD (49152) và Lockdown (62078)
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        airliftLogSink = log
        al_log_init(airliftLogCallback, nil)
        
        let hosts = candidates()
        log("[Airlift] Đang quét các IP khả thi cho LocalDevVPN 1.3.0: \(hosts.joined(separator: ", "))")
        
        var fallbackHost: String = "10.7.0.1" // Fallback an toàn nhất
        
        for host in hosts {
            // Ưu tiên thử cổng RSD (49152) - cổng chính của Airlift
            let isRSD = await canConnect(host: host, port: 49152, timeout: 0.8)
            if isRSD {
                _ = al_set_target_host(host)
                log("[Airlift] ✅ Kết nối RSD (49152) thành công tại: \(host)")
                return host
            }
            
            // Nếu không có RSD, thử cổng Lockdown (62078) - dự phòng
            let isLockdown = await canConnect(host: host, port: 62078, timeout: 0.8)
            if isLockdown {
                _ = al_set_target_host(host)
                log("[Airlift] ✅ Kết nối Lockdown (62078) thành công tại: \(host)")
                return host
            }
            
            log("[Airlift] ❌ \(host) không phản hồi cổng 49152 hoặc 62078.")
            
            // Cập nhật fallback nếu tìm thấy IP khác "127.0.0.1"
            if host != "127.0.0.1" && fallbackHost == "10.7.0.1" {
                fallbackHost = host
            }
        }
        
        // Nếu tất cả đều tịt (iOS chặn ping), vẫn ép IP fallback để thư viện C thử
        log("[Airlift] ⚠️ Không ping được IP nào. Thử ép IP fallback: \(fallbackHost)")
        _ = al_set_target_host(fallbackHost)
        return fallbackHost
    }
    
    // Hàm ping TCP thô
    private static func canConnect(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                
                if inet_pton(AF_INET, host, &addr.sin_addr) != 1 {
                    cont.resume(returning: false)
                    return
                }
                
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    cont.resume(returning: false)
                    return
                }
                defer { close(fd) }
                
                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                
                let rc = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                
                if rc == 0 {
                    cont.resume(returning: true)
                    return
                }
                
                if errno != EINPROGRESS {
                    cont.resume(returning: false)
                    return
                }
                
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let timeoutMs = Int32(timeout * 1000)
                let pollResult = poll(&pfd, 1, timeoutMs)
                
                if pollResult <= 0 {
                    cont.resume(returning: false)
                    return
                }
                
                var soError: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
                cont.resume(returning: soError == 0)
            }
        }
    }
}