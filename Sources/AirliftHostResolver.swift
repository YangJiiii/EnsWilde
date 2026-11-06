//  AirliftHostResolver.swift
//  EnsWilde
//
//  Cấu hình target host cho Airlift FFI.
//  Airlift sẽ tự dial RSD 49152 trước, fallback Lockdown 62078 khi cần.
//  Cả hai cổng đều đi qua interface utun của VPN → không cần setenv USBMUXD.

import Foundation
import AirliftFFI

enum AirliftHostResolver {

    /// IP loopback mặc định của LocalDevVPN / SideStore.
    static let defaultTargetIP = "10.7.0.1"

    /// Các IP fallback nếu người dùng dùng VPN khác.
    static let fallbackHosts: [String] = [
        "10.7.0.1",   // LocalDevVPN / SideStore
        "172.16.0.1", // Một số VPN loopback khác
        "10.0.0.1"
    ]

    /// Set target host cho Airlift. Trả về IP đã chọn.
    @discardableResult
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        guard AirliftNetworkStatus.isVPNTunnelPresent() else {
            log("[Airlift] ⚠️ VPN chưa bật — tunnel RSD 49152 sẽ không hoạt động.")
            return nil
        }

        // 1. Set IP chính cho lõi C
        let primary = defaultTargetIP
        _ = al_set_target_host(primary)

        // 2. Đăng ký thêm fallback hosts (Airlift tự thử theo thứ tự khi connect)
        let cHosts: [UnsafePointer<CChar>?] = fallbackHosts.map { strdup($0) }
        defer { cHosts.forEach { if let p = $0 { free(p) } } }
        _ = cHosts.withUnsafeBufferPointer { buf in
            al_set_target_hosts(buf.baseAddress, fallbackHosts.count)
        }

        // 3. (Optional) đặt biến môi trường cho các lib phụ trợ khác trong Rust core.
        setenv("AIRLIFT_HOST", primary, 1)

        log("[Airlift] Target host = \(primary) — RSD 49152 + Lockdown 62078 (via VPN utun)")
        return primary
    }

    /// Xoá cấu hình khi thoát app hoặc đổi mạng.
    static func reset() {
        al_clear_target_hosts()
        unsetenv("AIRLIFT_HOST")
    }
}