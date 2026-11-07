//  RebootHelper.swift
//  EnsWilde
//
//  Dùng Private API để khởi động lại thiết bị (Reboot).
//  Thay vì chỉ kill SpringBoard (Respring).

import Foundation
import UIKit

enum RebootHelper {
    
    /// Khởi động lại thiết bị (Reboot)
    static func rebootDevice() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 1. Thử dùng Private API của FrontBoardServices hoặc UIDevice
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["-9", "backboardd"] // Kill backboardd sẽ khiến máy tự reboot
            
            do {
                try task.run()
            } catch {
                print("[Reboot] Fallback to SpringBoard kill: \(error)")
                // Fallback: Kill SpringBoard nếu không kill được backboardd
                let fallback = Process()
                fallback.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                fallback.arguments = ["-9", "SpringBoard"]
                try? fallback.run()
            }
        }
    }
    
    /// Cách 2 (Nếu cách trên không được): Gọi qua XPC hoặc Private Framework
    static func forceReboot() {
        // Gọi _reboot() từ libsystem_kernel
        let handle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW)
        if let sym = dlsym(handle, "reboot") {
            typealias RebootFunc = @convention(c) (Int32) -> Int32
            let reboot = unsafeBitCast(sym, to: RebootFunc.self)
            _ = reboot(0x80000000 | 0x12345678) // Lệnh reboot kernel
        }
        dlclose(handle)
    }
}
