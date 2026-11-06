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
        
        if let override = UserDefaults.standard.string(forKey: "TunnelDeviceIP"),
           !override.isEmpty,
           override != "127.0.0.1" {
            out.append(override)
        }
        
        if let detected = detectFromInterfaces(), !out.contains(detected) {
            out.append(detected)
        }
        
        // Thêm các IP dự phòng phổ biến của LocalDevVPN
        for ip in ["10.7.0.1", "10.7.1.1", "10.7.0.3", "198.18.0.1"] where !out.contains(ip) {
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
            
            let name = String(cString: cur.pointee.ifa_name)
            // Chỉ lấy IP của interface utun (VPN)
            if name.hasPrefix("utun") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                if !ip.isEmpty && ip != "127.0.0.1" {
                    return ip
                }
            }
        }
        return nil
    }
    
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        airliftLogSink = log
        al_log_init(airliftLogCallback, nil)
        
        let hosts = candidates()
        log("[Airlift] Available hosts: \(hosts.joined(separator: ", "))")
        
        // Lấy IP đầu tiên (ưu tiên IP từ interface utun hoặc UserDefaults)
        if let bestHost = hosts.first {
            _ = al_set_target_host(bestHost)
            log("[Airlift] Selected: \(bestHost)")
            return bestHost
        }
        
        return nil
    }
}