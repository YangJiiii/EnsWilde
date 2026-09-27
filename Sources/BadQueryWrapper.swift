import Foundation

enum BadQueryError: Error, LocalizedError {
    case cantResolve
    case cantCreateQuery
    case outsideSandbox
    case kernelDenied
    case unknown(Int32)

    var errorDescription: String? {
        switch self {
        case .cantResolve:       return "bad_query: cannot resolve symbol"
        case .cantCreateQuery:   return "bad_query: cannot create sandbox query"
        case .outsideSandbox:    return "bad_query: path outside sandbox"
        case .kernelDenied:      return "bad_query: kernel denied"
        case .unknown(let code): return "bad_query: unknown error \(code)"
        }
    }
}

enum BadQueryWrapper {
    static func writeFile(at path: String, data: Data) throws {
        var cPath = path.cString(using: .utf8)!
        let handle = bad_query(&cPath, false, nil, false)

        switch handle {
        case -1: throw BadQueryError.cantResolve
        case -2: throw BadQueryError.cantCreateQuery
        case -3: throw BadQueryError.outsideSandbox
        case -4: throw BadQueryError.kernelDenied
        default: break
        }

        guard handle > 0 else { throw BadQueryError.unknown(handle) }
        defer { bad_query_release(handle) }

        try data.write(to: URL(fileURLWithPath: path))
    }
}