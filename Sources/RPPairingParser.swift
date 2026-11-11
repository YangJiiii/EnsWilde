import Foundation

struct RPPairingData {
    let publicKey: Data
    let privateKey: Data
    let identifier: String
    let altIRK: Data
}

enum RPPairingError: Error, LocalizedError {
    case invalidFormat
    case missingKey(String)
    case unsupportedExtension

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "File không phải định dạng plist hợp lệ."
        case .missingKey(let key): return "File pairing bị thiếu key bắt buộc: \(key). Vui lòng dùng file chuẩn!"
        case .unsupportedExtension: return "Chỉ chấp nhận file .plist hoặc .mobiledevicepairing!"
        }
    }
}

enum RPPairingParser {
    static func parse(url: URL) throws -> RPPairingData {
        // 1. Check extension
        let ext = url.pathExtension.lowercased()
        guard ext == "plist" || ext == "mobiledevicepairing" else {
            throw RPPairingError.unsupportedExtension
        }

        let data = try Data(contentsOf: url)
        
        // 2. Check plist format (XML or Binary) - PropertyListSerialization tự hiểu cả 2
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw RPPairingError.invalidFormat
        }

        // 3. Check required keys (Khớp chính xác với format XML m gửi)
        guard let publicKey = plist["public_key"] as? Data else {
            throw RPPairingError.missingKey("public_key")
        }
        guard let privateKey = plist["private_key"] as? Data else {
            throw RPPairingError.missingKey("private_key")
        }
        guard let identifier = plist["identifier"] as? String else {
            throw RPPairingError.missingKey("identifier")
        }
        guard let altIRK = plist["alt_irk"] as? Data else {
            throw RPPairingError.missingKey("alt_irk")
        }

        return RPPairingData(
            publicKey: publicKey,
            privateKey: privateKey,
            identifier: identifier,
            altIRK: altIRK
        )
    }
}