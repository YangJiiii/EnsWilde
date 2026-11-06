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
    
    // Tập hợp tất cả các IP có thể có của Tunnel trên mọi nền tảng
    static func candidates() -> [String] {
        var out: [String] = []
        
        // 1. Lấy từ cài đặt thủ công (nếu có)
        if let override = UserDefaults.standard.string(forKey: "TunnelDeviceIP"), !override.isEmpty {
            out.append(override)
        }
        
        // 2. Tự động quét tất cả interface mạng (utun)
        if let detected = detectFromInterfaces() {
            for ip in detected where !out.contains(ip) {
                out.append(ip)
            }
        }
        
        // 3. Danh sách IP phổ biến của các tool (StikDebug, LocalDevVPN, SideStore)
        let commonIPs = [
            "127.0.0.1",      // Loopback
            "10.7.0.1",       // LocalDevVPN / StikDebug mặc định
            "10.7.0.2",
            "10.7.0.3",
            "10.7.1.1",       // LocalDevVPN biến thể
            "10.7.1.2",
            "172.16.0.1",     // StikDebug / WireGuard
            "198.18.0.1",     // SideStore mặc định
            "::1",            // IPv6 Loopback
            "fd00::1"         // IPv6 Tunnel
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
            if name.hasPrefix("utun") || name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                
                // Bỏ qua các IP rác
                if !ip.isEmpty && ip != "0.0.0.0" && ip != "127.0.0.1" && !ip.hasPrefix("fe80") {
                    // Xoá đuôi %en0 của IPv6
                    let cleanIP = ip.components(separatedBy: "%").first ?? ip
                    if !foundIPs.contains(cleanIP) {
                        foundIPs.append(cleanIP)
                    }
                }
            }
        }
        return foundIPs.isEmpty ? nil : foundIPs
    }
    
    // Tìm IP tốt nhất (Ping thử cổng RSD 49152, nếu không được thì thử cổng Lockdown 62078)
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        airliftLogSink = log
        al_log_init(airliftLogCallback, nil)
        
        let hosts = candidates()
        log("[Airlift] Đang quét các IP khả thi: \(hosts.joined(separator: ", "))")
        
        var fallbackHost: String = "127.0.0.1"
        
        for host in hosts {
            // Ưu tiên thử cổng RSD (49152)
            let isRSD = await canConnect(host: host, port: 49152, timeout: 0.8)
            if isRSD {
                _ = al_set_target_host(host)
                log("[Airlift] ✅ Đã kết nối RSD (49152) thành công tại: \(host)")
                return host
            }
            
            // Nếu không có RSD, thử cổng Lockdown (62078)
            let isLockdown = await canConnect(host: host, port: 62078, timeout: 0.8)
            if isLockdown {
                _ = al_set_target_host(host)
                log("[Airlift] ✅ Đã kết nối Lockdown (62078) thành công tại: \(host)")
                return host
            }
            
            // Lưu lại làm fallback nếu tất cả đều tịt
            if host != "127.0.0.1" && fallbackHost == "127.0.0.1" {
                fallbackHost = host
            }
            log("[Airlift] ❌ \(host) không phản hồi cổng RSD/Lockdown.")
        }
        
        // Nếu tất cả đều tịt (do iOS chặn ping), tự động ép IP tốt nhất cho thư viện C thử
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