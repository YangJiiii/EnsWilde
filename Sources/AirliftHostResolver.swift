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
    
    static func candidates() -> [String] {
        var out: [String] = []
        
        if let override = UserDefaults.standard.string(forKey: "TunnelDeviceIP"), !override.isEmpty {
            out.append(override)
        }
        
        if let detected = detectFromInterfaces() {
            for ip in detected where !out.contains(ip) {
                out.append(ip)
            }
        }
        
        let commonIPs = ["10.7.0.1", "10.7.1.1", "127.0.0.1", "172.16.0.1", "198.18.0.1"]
        for ip in commonIPs where !out.contains(ip) {
            out.append(ip)
        }
        
        return out
    }
    
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
    
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        airliftLogSink = log
        al_log_init(airliftLogCallback, nil)
        
        let hosts = candidates()
        log("[Airlift] Đang quét IP (Hỗ trợ cả StikDebug & LocalDevVPN): \(hosts.joined(separator: ", "))")
        
        // Tìm IP có kết nối tốt nhất (ưu tiên 62078 cho StikDebug, 49152 cho SideStore)
        for host in hosts {
            let hasLockdown = await canConnect(host: host, port: 62078, timeout: 0.8)
            let hasRSD = await canConnect(host: host, port: 49152, timeout: 0.8)
            
            if hasLockdown || hasRSD {
                _ = al_set_target_host(host)
                // Ép biến môi trường để Airlift C không tự ý nhảy sang 172.16.0.1
                setenv("USBMUXD_SOCKET_ADDRESS", "\(host):62078", 1)
                setenv("AIRLIFT_HOST", host, 1)
                
                if hasLockdown {
                    log("[Airlift] ✅ Kết nối Lockdown (62078) tại: \(host)")
                } else {
                    log("[Airlift] ✅ Kết nối RSD (49152) tại: \(host)")
                }
                return host
            }
            log("[Airlift] ❌ \(host) không phản hồi.")
        }
        
        // Fallback: Nếu StikDebug bật nhưng iOS chặn ping, tự động ép 10.7.0.1
        let fallback = hosts.first ?? "10.7.0.1"
        _ = al_set_target_host(fallback)
        setenv("USBMUXD_SOCKET_ADDRESS", "\(fallback):62078", 1)
        setenv("AIRLIFT_HOST", fallback, 1)
        log("[Airlift] ⚠️ Ép IP: \(fallback) và set Environment Variables")
        return fallback
    }
    
    private static func canConnect(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                
                if inet_pton(AF_INET, host, &addr.sin_addr) != 1 {
                    cont.resume(returning: false); return
                }
                
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { cont.resume(returning: false); return }
                defer { close(fd) }
                
                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                
                let rc = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                
                if rc == 0 { cont.resume(returning: true); return }
                if errno != EINPROGRESS { cont.resume(returning: false); return }
                
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                if poll(&pfd, 1, Int32(timeout * 1000)) <= 0 {
                    cont.resume(returning: false); return
                }
                
                var soError: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
                cont.resume(returning: soError == 0)
            }
        }
    }
}