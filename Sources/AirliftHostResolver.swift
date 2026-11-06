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
    
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        airliftLogSink = log
        al_log_init(airliftLogCallback, nil)
        
        let hosts = candidates()
        log("[Airlift] Danh sách IP sẽ thử: \(hosts.joined(separator: ", "))")
        
        // 1. Ép toàn bộ danh sách IP vào lõi C
        var cStrings = hosts.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        
        cStrings.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                _ = al_set_target_hosts(base, hosts.count)
            }
        }
        
        // 2. Set IP đầu tiên làm mặc định (thường là 10.7.0.1)
        let primary = hosts.first ?? "10.7.0.1"
        _ = al_set_target_host(primary)
        
        log("[Airlift] Đã nạp danh sách IP vào lõi C. Primary: \(primary)")
        return primary
    }
    
    static func candidates() -> [String] {
        var out: [String] = []
        
        // Lấy từ cài đặt
        if let override = UserDefaults.standard.string(forKey: "TunnelDeviceIP"), !override.isEmpty {
            out.append(override)
        }
        
        // Tự động dò
        if let detected = detectFromInterfaces() {
            for ip in detected where !out.contains(ip) {
                out.append(ip)
            }
        }
        
        // Các IP mặc định của LocalDevVPN / SideStore / StikDebug
        let defaults = ["10.7.0.1", "10.7.1.1", "10.7.0.2", "127.0.0.1"]
        for ip in defaults where !out.contains(ip) {
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
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            
            let name = String(cString: cur.pointee.ifa_name)
            if name.hasPrefix("utun") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                if !ip.isEmpty && ip != "127.0.0.1" && !foundIPs.contains(ip) {
                    foundIPs.append(ip)
                }
            }
        }
        return foundIPs.isEmpty ? nil : foundIPs
    }
}