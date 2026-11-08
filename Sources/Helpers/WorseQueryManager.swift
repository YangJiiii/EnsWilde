import Foundation

enum WorseQueryManager {
    static let mgCacheDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
    
    /// Đảm bảo app có quyền truy cập vào thư mục chứa MobileGestalt.plist
    static func ensureMobileGestaltAccess() throws {
        let wq = WorseQuery()
        // 1. Xin quyền cho thư mục cha
        let res = wq.grantAccess(atPath: mgCacheDir)
        guard res.0 else {
            // Thử cấp trên nếu thư mục con fail
            let parentRes = wq.grantAccess(atPath: "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library")
            if !parentRes.0 {
                throw NSError(domain: "WorseQuery", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Không thể xin quyền WorseQuery cho MobileGestalt. (Lỗi: \(res.2))"
                ])
            }
            return
        }
    }
}
