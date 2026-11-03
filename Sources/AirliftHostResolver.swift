import Foundation
import Network
import AirliftFFI

// MARK: - Log sink toàn cục
// Closure C không được capture context, phải dùng global var để lưu handler
private var airliftLogSink: ((String) -> Void)?

// MARK: - C Callback
private let airliftLogCallback: ALLogCallback = { (ctx, msg) in
    guard let msg = msg else { return }
    let line = String(cString: msg)
    airliftLogSink?(line)
}

enum AirliftHostResolver {
    
    static func candidates() -> [String] {
        var out: [String] = []
        
        if let override = UserDefaults.standard.string(forKey: "TunnelDeviceIP"),
           !override.isEmpty,
           override != "127.0.0.1",
           !out.contains(override) {
            out.append(override)
        }
        
        if let detected = detectFromInterfaces(), !out.contains(detected) {
            out.append(detected)
        }
        
        for ip in ["10.7.0.1", "10.7.0.2", "10.7.0.3", "198.18.0.1"] where !out.contains(ip) {
            out.append(ip)
        }
        
        return out
    }
    
    static func detectFromInterfaces() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &host, socklen_t(host.count),
                        nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("10.7.0.") || ip.hasPrefix("198.18.0.") {
                return ip
            }
        }
        return nil
    }
    
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        airliftLogSink = log
        
        // Đăng ký log callback 1 lần duy nhất
        al_log_init(airliftLogCallback, nil)
        
        let hosts = candidates()
        log("[Airlift] Probing hosts: \(hosts.joined(separator: ", "))")
        
        for host in hosts where host != "127.0.0.1" {
            let ok = await canConnect(host: host, port: 49152, timeout: 1.2)
            if ok {
                _ = al_set_target_host(host)
                log("[Airlift] Selected: \(host)")
                return host
            }
            log("[Airlift] \(host) unreachable")
        }
        return nil
    }
    
    private static func canConnect(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
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