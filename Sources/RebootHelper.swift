//  RebootHelper.swift
//  EnsWilde
//
//  Cố gắng reboot máy thật bằng syscall reboot().
//  Nếu sandbox chặn (app sideload thường), fallback về NeoSpring respring
//  để ít nhất SpringBoard/TelephonyUI reload lại cache.

import Foundation
import Darwin

enum RebootHelper {

    /// Reboot máy nếu có quyền, fallback respring nếu không.
    static func rebootDevice() {
        print("[Reboot] Attempting kernel reboot...")

        // 1. Thử gọi syscall reboot() qua libSystem
        if tryKernelReboot() {
            return
        }
        print("[Reboot] Kernel reboot failed (sandbox). Trying launchd...")

        // 2. Thử kill launchd — kernel sẽ trigger reboot userspace
        if tryKillLaunchd() {
            return
        }
        print("[Reboot] launchd kill failed (sandbox). Falling back to NeoSpring respring.")

        // 3. Fallback: NeoSpring respring (đủ để reload cache passcode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            RespringHelper.triggerNeoSpring()
        }
    }

    // MARK: - Private

    /// Gọi syscall `reboot(RB_AUTOBOOT)` qua dlopen. Trả true nếu không lỗi.
    private static func tryKernelReboot() -> Bool {
        guard let handle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW),
              let sym = dlsym(handle, "reboot") else {
            return false
        }
        defer { dlclose(handle) }

        typealias RebootFunc = @convention(c) (Int32) -> Int32
        let rebootFunc = unsafeBitCast(sym, to: RebootFunc.self)

        // RB_AUTOBOOT = 0x01234567 theo <sys/reboot.h>
        let RB_AUTOBOOT: Int32 = 0x01234567
        let rc = rebootFunc(RB_AUTOBOOT)
        return rc == 0
    }

    /// Kill launchd (PID 1) — kernel sẽ reboot userspace. Trả true nếu thành công.
    private static func tryKillLaunchd() -> Bool {
        let rc = kill(1, SIGTERM)
        return rc == 0
    }
}