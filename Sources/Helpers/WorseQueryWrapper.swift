import Foundation

enum WorseQueryError: Error, LocalizedError {
    case cantResolve
    case cantCreateQuery
    case outsideSandbox
    case kernelDenied
    case unknown(Int64)

    var errorDescription: String? {
        switch self {
        case .cantResolve:       return "worse_query: cannot resolve symbol"
        case .cantCreateQuery:   return "worse_query: cannot create sandbox query"
        case .outsideSandbox:    return "worse_query: path outside sandbox"
        case .kernelDenied:      return "worse_query: kernel denied"
        case .unknown(let code): return "worse_query: unknown error \(code)"
        }
    }
}

enum WorseQueryWrapper {
    /// Ghi file ra ngoài sandbox qua worse_query.
    /// - Parameters:
    ///   - path: đường dẫn tuyệt đối tới file cần ghi
    ///   - data: dữ liệu cần ghi
    ///   - groupIdentifier: App Group ID nếu cần (khác nil khi ghi vào App Group)
    ///   - isGroup: true nếu target nằm trong App Group (chỉ áp dụng iOS 26)
    static func writeFile(
        at path: String,
        data: Data,
        groupIdentifier: String? = nil,
        isGroup: Bool = false
    ) throws {
        // worse_query(NSString *path, NSString *group, bool alt_flags, bool create_dir)
        // - path:       đường dẫn đích
        // - group:      App Group ID (nil nếu không dùng)
        // - alt_flags:  true = dùng flag cho App Group (tương đương is_group cũ)
        // - create_dir: true = tạo container nếu chưa tồn tại (tương đương create cũ)
        let handle = worse_query(path, groupIdentifier, isGroup, true)

        // Map mã lỗi — giữ tương thích với bad_query cũ
        switch handle {
        case -1: throw WorseQueryError.cantResolve
        case -2: throw WorseQueryError.cantCreateQuery
        case -3: throw WorseQueryError.outsideSandbox
        case -4: throw WorseQueryError.kernelDenied
        default: break
        }

        guard handle > 0 else {
            throw WorseQueryError.unknown(handle)
        }
        defer { worse_query_release(handle) }

        try data.write(to: URL(fileURLWithPath: path))
    }
}
