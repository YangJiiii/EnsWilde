//  AirliftHostResolver.swift
//  EnsWilde

import Foundation
import AirliftFFI

enum AirliftHostResolver {

    struct ResolutionResult {
        let host: String
        let rsdReachable: Bool
        let lockdownReachable: Bool
    }

    /// Danh sách fallback cứng (dùng khi không phát hiện được IP động nào route được).
    static let fallbackHosts: [String] = [
        "10.7.0.1", "10.7.1.1",
        "172.16.0.1",
        "10.0.0.1"
    ]

    @discardableResult
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        // 1. Quét động toàn bộ IP của tunnel interfaces
        let discovered = NetworkStatus.detectAllTunnelIPs()
        log("[Airlift] IP phát hiện từ tunnel: \(discovered.isEmpty ? "không có" : discovered.joined(separator: ", "))")

        // Tạo danh sách ứng viên: ưu tiên IP động, sau đó fallback chưa có trong danh sách động
        var candidates = discovered
        for fb in fallbackHosts where !candidates.contains(fb) {
            candidates.append(fb)
        }

        var resolved: ResolutionResult? = nil

        // 2. Probe TCP 49152 / 62078 trên từng ứng viên
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
            log("[Airlift] ❌ Không reach được RSD 49152 hoặc Lockdown 62078 trên bất kỳ IP nào.")
            log("[Airlift]    → Đảm bảo LocalDevVPN/StikDebug đã 'Connected'.")
            return nil
        }

        // 3. Set target host cho Airlift
        let setRC = al_set_target_host(result.host)
        if setRC != 0 {
            log("[Airlift] ⚠️ al_set_target_host(\(result.host)) trả mã \(setRC).")
        } else {
            log("[Airlift] ✅ Target host = \(result.host)")
        }

        if result.rsdReachable {
            log("[Airlift] → Airlift sẽ dial RSD 49152 trước.")
        } else if result.lockdownReachable {
            log("[Airlift] ⚠️ RSD 49152 đóng, Airlift dùng Lockdown 62078 (fallback).")
        }

        return result.host
    }

    static func reset() {
        al_clear_target_hosts()
    }
}