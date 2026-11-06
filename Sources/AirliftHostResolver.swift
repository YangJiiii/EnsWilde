import Foundation
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
        
        // Ép cứng IP của LocalDevVPN làm IP duy nhất để thư viện C kết nối
        let fixedIP = "10.7.0.1"
        
        log("[Airlift] Đang ép kết nối tới IP Tunnel: \(fixedIP)")
        
        // Gọi hàm C để set IP, bỏ qua bước Ping (vì Ping hay bị lỗi sandbox)
        _ = al_set_target_host(fixedIP)
        
        return fixedIP
    }
}