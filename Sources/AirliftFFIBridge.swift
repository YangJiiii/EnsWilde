//  AirliftFFIBridge.swift
//  EnsWilde
//
//  Cầu nối Swift ↔ Airlift FFI. Chịu trách nhiệm:
//  - Đăng ký log callback C convention
//  - Free heap string (al_string_free)
//  - Chuyển blocking call thành async

import Foundation
import AirliftFFI

final class AirliftFFIBridge {

    // MARK: - Log callback (giữ reference để không bị giải phóng)

    /// Tạo C callback giữ chuỗi sống tới khi stream dừng.
    static func makeLogCallback(
        onLine: @escaping (String) -> Void
    ) -> (ALLogCallback, UnsafeMutableRawPointer) {
        // Bridge class: giữ closure Swift trên heap
        let box = LogBox(onLine: onLine)
        let opaque = Unmanaged.passRetained(box).toOpaque()

        let cb: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { ctx, msg in
            guard let ctx = ctx else { return }
            let box = Unmanaged<LogBox>.fromOpaque(ctx).takeUnretainedValue()
            guard let msg = msg else { return }
            let line = String(cString: msg)
            // Callback được Rust gọi từ arbitrary thread — đẩy về main để UI-safe.
            DispatchQueue.main.async { box.onLine(line) }
        }
        return (cb, opaque)
    }

    static func releaseLogCallback(_ ctx: UnsafeMutableRawPointer) {
        Unmanaged<LogBox>.fromOpaque(ctx).release()
    }

    // MARK: - Utils

    /// Lấy và free heap char* mà Airlift trả về.
    static func takeCString(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr = ptr else { return nil }
        let s = String(cString: ptr)
        al_string_free(ptr)
        return s
    }
}

// MARK: - Box cho callback

final class LogBox {
    let onLine: (String) -> Void
    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }
}