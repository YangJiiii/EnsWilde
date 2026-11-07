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

    static let candidates: [String] = [
        "10.7.0.1",   // LocalDevVPN / StikDebug / SideStore
        "172.16.0.1",
        "10.0.0.1"
    ]

    @discardableResult
    static func bestAvailable(log: @escaping (String) -> Void) async -> String? {
        log("[Airlift] Đang probe TCP tới RSD 49152 / Lockdown 62078...")

        var resolved: ResolutionResult? = nil
        
        // Probe TCP trực tiếp. Không cần quan tâm tunnel IP là gì.
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
            log("[Airlift] ❌ Không reach được RSD 49152 hoặc Lockdown 62078.")
            log("[Airlift]    → Mở LocalDevVPN và đảm bảo nó báo 'Connected'.")
            log("[Airlift]    → Nếu đã Connected, thử tắt/bật lại VPN.")
            return nil
        }

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