import Foundation
import AirliftFFI

enum AirliftHostResolver {
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        // Ép cứng IP của LocalDevVPN / SideStore
        let targetIP = "10.7.0.1"
        
        // 1. Set IP cho lõi C
        _ = al_set_target_host(targetIP)
        
        // 2. Set biến môi trường để lõi C không fallback về 172.16.0.1
        setenv("AIRLIFT_HOST", targetIP, 1)
        setenv("USBMUXD_SOCKET_ADDRESS", "\(targetIP):62078", 1)
        
        log("[Airlift] Đã ép IP Target: \(targetIP) (Hỗ trợ cả RSD & Lockdown)")
        return targetIP
    }
}