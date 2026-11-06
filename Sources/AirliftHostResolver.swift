//  AirliftHostResolver.swift
//  EnsWilde
//
//  Chọn target host cho Airlift một cách chắc chắn:
//   1. Kiểm tra tunnel VPN thực sự có IP loopback (không chỉ utun bất kỳ)
//   2. TCP-probe cổng RSD 49152 và Lockdown 62078
//   3. Chỉ set target host nếu ít nhất một trong hai cổng reachable
//   4. Airlift tự dial RSD 49152 trước, fallback Lockdown 62078

import Foundation
import AirliftFFI

enum AirliftHostResolver {

    struct ResolutionResult {
        let host: String
        let rsdReachable: Bool
        let lockdownReachable: Bool
    }

    /// Danh sách host sẽ thử, theo thứ tự ưu tiên.
    static let candidates: [String] = [
        "10.7.0.1",   // LocalDevVPN / StikDebug / SideStore
        "172.16.0.1", // VPN loopback khác
        "10.0.0.1"
    ]

    /// Probe và set target host. Trả về `nil` nếu không có host nào reachable.
    @discardableResult
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        // 1. Bước 1 — VPN tunnel phải có IP loopback
        guard let tunnelIP = NetworkStatus.detectActiveTunnelIP() else {
            log("[Airlift] ❌ Không có tunnel VPN nào có IP 10.7.0.x / 172.16.0.x.")
            log("[Airlift]    → Mở LocalDevVPN hoặc StikDebug và bật tunnel trước.")
            return nil
        }
        log("[Airlift] Tunnel IP hiện tại: \(tunnelIP)")

        // 2. Bước 2 — TCP-probe từng candidate (RSD 49152 + Lockdown 62078)
        var resolved: ResolutionResult? = nil
        for host in candidates {
            let (rsd, lock) = NetworkStatus.probeDevicePorts(host: host, timeoutMs: 800)
            let rsdStr  = rsd  ? "✅" : "❌"
            let lockStr = lock ? "✅" : "❌"
            log("[Airlift] Probe \(host) → RSD 49152 \(rsdStr) | Lockdown 62078 \(lockStr)")

            if rsd || lock {
                resolved = ResolutionResult(host: host, rsdReachable: rsd, lockdownReachable: lock)
                break
            }
        }

        guard let result = resolved else {
            log("[Airlift] ❌ Không reach được RSD 49152 hoặc Lockdown 62078 trên bất kỳ candidate nào.")
            log("[Airlift]    → VPN có thể đang bật nhưng chưa route. Thử:")
            log("[Airlift]      1. Tắt/bật lại LocalDevVPN")
            log("[Airlift]      2. Mở một app khác (vd. SideStore) để kích hoạt tunnel")
            log("[Airlift]      3. Kiểm tra pairing file còn hợp lệ")
            return nil
        }

        // 3. Bước 3 — Set target host cho Airlift
        let setRC = al_set_target_host(result.host)
        if setRC != 0 {
            log("[Airlift] ⚠️ al_set_target_host(\(result.host)) trả mã \(setRC).")
        } else {
            log("[Airlift] ✅ Target host = \(result.host)")
        }

        if result.rsdReachable {
            log("[Airlift] → Airlift sẽ dial RSD 49152 trước.")
        } else if result.lockdownReachable {
            log("[Airlift] ⚠️ RSD 49152 đóng, Airlift sẽ dùng Lockdown 62078 (fallback).")
            log("[Airlift]    iOS 17+ có thể fail — kiểm tra VPN route tới 10.7.0.1:49152.")
        }

        return result.host
    }

    /// Reset khi thoát app hoặc đổi mạng.
    static func reset() {
        al_clear_target_hosts()
    }

    /// Chẩn đoán toàn diện — gọi từ Settings để xem app đang thấy gì.
    static func diagnose(log: @escaping (String) -> Void) {
        log("=== Airlift / Network Diagnostics ===")
        NetworkStatus.dumpInterfaces(log: log)

        log("--- Tunnel IP ---")
        if let ip = NetworkStatus.detectActiveTunnelIP() {
            log("Active tunnel IP: \(ip)")
        } else {
            log("Active tunnel IP: ❌ không có")
        }

        log("--- Port probe ---")
        for host in candidates {
            let (rsd, lock) = NetworkStatus.probeDevicePorts(host: host, timeoutMs: 800)
            log("\(host): RSD 49152=\(rsd ? "✅" : "❌") | Lockdown 62078=\(lock ? "✅" : "❌")")
        }

        log("--- Env ---")
        if let env = ProcessInfo.processInfo.environment["AIRLIFT_HOST"] {
            log("AIRLIFT_HOST=\(env)")
        } else {
            log("AIRLIFT_HOST=<không set>")
        }
        log("=== End ===")
    }
}