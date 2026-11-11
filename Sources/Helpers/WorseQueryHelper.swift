import Foundation

/// Drop-in replacement cho BadQuery, dùng worse_query + pathleak.
/// Interface công khai giữ y hệt BadQuery cũ để các call site chỉ cần
/// đổi `BadQuery()` → `WorseQuery()` và giữ nguyên `grantAccess(...)`.
class WorseQuery {

    /// App Group identifier mà worse_query yêu cầu trên một số iOS version.
    /// Set 1 lần trước khi dùng nếu build của bạn cần, ví dụ:
    ///     WorseQuery.appGroupIdentifier = "group.com.yourdomain.enswilde"
    /// Nếu nil thì gọi worse_query với group = nil (giống bad_query cũ).
    static var appGroupIdentifier: String? = nil

    /// Cấp quyền truy cập filesystem cho `directory` (map sang worse_query()).
    /// Trả về (success, handle, errorMessage) — cùng shape như BadQuery cũ.
    @discardableResult
    func grantAccess(atPath directory: String, toFileName fileName: String = "") -> (Bool, Int64, String) {
        // worse_query(NSString *path, NSString *group, bool alt_flags, bool create_dir)
        let handle = worse_query(directory, WorseQuery.appGroupIdentifier, false, false)
        if handle != 0 {
            return (true, handle, "")
        }
        return (false, handle, "worse_query failed (code \(handle)) for path: \(directory)")
    }

    /// Liệt kê entry của thư mục qua pathleak (thay cho bad_query_list).
    func getPathsOfDir(atPath directory: String, maxInode: UInt64 = 1000) -> [String] {
        (pathleak(directory, maxInode) as? [String]) ?? []
    }

    /// Giải phóng handle trả về từ grantAccess() (nếu cần).
    func releaseHandle(_ handle: Int64) {
        worse_query_release(handle)
    }
}
