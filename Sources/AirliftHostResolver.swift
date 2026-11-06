import Foundation

enum AirliftHostResolver {
    static func bestAvailable(log: (String) -> Void) async -> String? {
        log("Đang kiểm tra kết nối RSD Tunnel...")
        
        // Ưu tiên tuyệt đối địa chỉ loopback của LocalDevVPN
        let loopbackIP = "10.7.0.1"
        
        // Kiểm tra xem interface utun có tồn tại không (chỉ để log)
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            defer { freeifaddrs(ifaddr) }
            var ptr = ifaddr
            var foundUtun = false
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("utun") {
                    foundUtun = true
                    break
                }
            }
            if foundUtun {
                log("✅ Đã phát hiện interface utun. Sử dụng loopback IP: \(loopbackIP)")
            } else {
                log("⚠️ Không tìm thấy interface utun, nhưng vẫn thử loopback IP: \(loopbackIP)")
            }
        }
        
        // Luôn trả về 10.7.0.1 cho Airlift FFI
        return loopbackIP
    }
}