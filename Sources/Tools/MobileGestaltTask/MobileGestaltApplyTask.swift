import Foundation
import UIKit
import AirliftFFI
import Darwin
import Security
import XPC

// MARK: - Native WorseQuery Bridge (Bypass AirliftFFI)
typealias ContainerQueryCreateFn = @convention(c) () -> OpaquePointer?
typealias ContainerQuerySetClassFn = @convention(c) (OpaquePointer?, UInt64) -> Void
typealias ContainerQuerySetGroupIdentifiersFn = @convention(c) (OpaquePointer?, xpc_object_t) -> Void
typealias ContainerQuerySetFlagsFn = @convention(c) (OpaquePointer?, UInt64) -> Void
typealias ContainerQuerySetPartFn = @convention(c) (OpaquePointer?, UInt64) -> Void
typealias ContainerQueryGetSingleResultFn = @convention(c) (OpaquePointer?) -> OpaquePointer?
typealias ContainerQueryFreeFn = @convention(c) (OpaquePointer?) -> Void
typealias ContainerCopySandboxTokenFn = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
typealias SandboxExtensionConsumeFn = @convention(c) (UnsafePointer<CChar>) -> Int64
typealias SandboxExtensionReleaseFn = @convention(c) (Int64) -> Int32
typealias XPCStringCreateFn = @convention(c) (UnsafePointer<CChar>) -> xpc_object_t
typealias XPCReleaseFn = @convention(c) (xpc_object_t) -> Void

@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelf(_ allocator: UnsafeRawPointer?) -> CFTypeRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlement(
    _ task: CFTypeRef,
    _ entitlement: CFString,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> CFTypeRef?

@_silgen_name("sandbox_extension_consume")
private func sandbox_extension_consume(_ token: UnsafePointer<CChar>) -> Int64

@_silgen_name("sandbox_extension_release")
private func sandbox_extension_release(_ handle: Int64) -> Int

final class NativeWorseQuery {
    static let shared = NativeWorseQuery()
    private var activeHandles: [Int64] = []
    private let RTLD_DEFAULT_HANDLE = UnsafeMutableRawPointer(bitPattern: -2)
    
    private var mcmHandle: UnsafeMutableRawPointer?
    private var queryCreate: ContainerQueryCreateFn?
    private var querySetClass: ContainerQuerySetClassFn?
    private var querySetGroupIds: ContainerQuerySetGroupIdentifiersFn?
    private var querySetFlags: ContainerQuerySetFlagsFn?
    private var querySetPart: ContainerQuerySetPartFn?
    private var queryGetSingleResult: ContainerQueryGetSingleResultFn?
    private var queryFree: ContainerQueryFreeFn?
    private var copySandboxToken: ContainerCopySandboxTokenFn?
    private var sandboxConsume: SandboxExtensionConsumeFn?
    private var sandboxRelease: SandboxExtensionReleaseFn?
    private var xpcStringCreate: XPCStringCreateFn?
    private var xpcRelease: XPCReleaseFn?
    
    init() { loadMCM() }
    
    private func loadMCM() {
        mcmHandle = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL)
        guard let handle = mcmHandle else { return }
        
        func sym<T>(_ name: String) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }
        
        queryCreate = sym("container_query_create")
        querySetClass = sym("container_query_set_class")
        querySetGroupIds = sym("container_query_set_group_identifiers")
        querySetFlags = sym("container_query_operation_set_flags")
        querySetPart = sym("container_query_operation_set_part")
        queryGetSingleResult = sym("container_query_get_single_result")
        queryFree = sym("container_query_free")
        copySandboxToken = sym("container_copy_sandbox_token")
        
        sandboxConsume = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "sandbox_extension_consume"), to: SandboxExtensionConsumeFn.self)
        sandboxRelease = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "sandbox_extension_release"), to: SandboxExtensionReleaseFn.self)
        xpcStringCreate = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "xpc_string_create"), to: XPCStringCreateFn.self)
        xpcRelease = unsafeBitCast(dlsym(RTLD_DEFAULT_HANDLE, "xpc_release"), to: XPCReleaseFn.self)
    }
    
    func grantAccess(appGroupID: String) -> Int64 {
        guard let create = queryCreate, let setClass = querySetClass, let setGroupIds = querySetGroupIds,
              let setFlags = querySetFlags, let setPart = querySetPart, let getResult = queryGetSingleResult,
              let qFree = queryFree, let copyToken = copySandboxToken, let consume = sandboxConsume,
              let strCreate = xpcStringCreate, let xpcRel = xpcRelease else { return -1 }
        
        let fm = FileManager.default
        guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return -1 }
        
        let cachesPath = groupURL.appendingPathComponent("Library/Caches").path
        let libPath = groupURL.appendingPathComponent("Library").path
        let backupCaches = groupURL.appendingPathComponent("Library/Caches.bqtool").path
        let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        
        try? fm.createDirectory(atPath: libPath, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: backupCaches)
        if fm.fileExists(atPath: cachesPath) { try? fm.moveItem(atPath: cachesPath, toPath: backupCaches) }
        
        do { try fm.createSymbolicLink(atPath: cachesPath, withDestinationPath: targetDir) } catch {
            if fm.fileExists(atPath: backupCaches) { try? fm.moveItem(atPath: backupCaches, toPath: cachesPath) }
            return -1
        }
        
        guard let query = create() else {
            cleanup(cachesPath, backupCaches)
            return -1
        }
        
        setClass(query, 7)
        let ident = appGroupID.withCString { strCreate($0) }
        setGroupIds(query, ident)
        setPart(query, 3)
        
        var result: OpaquePointer? = nil
        setFlags(query, 0x8100000000)
        result = getResult(query)
        if result == nil {
            setFlags(query, 0x8000000000)
            result = getResult(query)
        }
        
        guard result != nil else {
            qFree(query); xpcRel(ident); cleanup(cachesPath, backupCaches)
            return -1
        }
        
        guard let tokenPtr = copyToken(result) else {
            qFree(query); xpcRel(ident); cleanup(cachesPath, backupCaches)
            return -1
        }
        
        let consumed = consume(tokenPtr)
        free(tokenPtr); qFree(query); xpcRel(ident); cleanup(cachesPath, backupCaches)
        
        if consumed < 0 { return -1 }
        activeHandles.append(consumed)
        return consumed
    }
    
    private func cleanup(_ cachesPath: String, _ backupCaches: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: cachesPath)
        if fm.fileExists(atPath: backupCaches) { try? fm.moveItem(atPath: backupCaches, toPath: cachesPath) }
    }
    
    func releaseAll() {
        if let release = sandboxRelease {
            for h in activeHandles { _ = release(h) }
        }
        activeHandles.removeAll()
    }
}

enum MobileGestaltApplyTask {
    static var onDeviceMGPath: String { MGURL.fsGestaltURL.path }

    static func applyGestalt(store: GestaltStore,
                             onLogUpdate: @escaping (String) -> Void) async throws {
        let mgURL = URL(fileURLWithPath: onDeviceMGPath)

        guard store.mgCurrentDict.count > 0 else {
            throw mgError(-1, "Store rỗng. Chỉnh gì đó rồi Save Settings trước khi Apply.")
        }
        guard FileManager.default.fileExists(atPath: onDeviceMGPath) else {
            throw mgError(-2, "Không tìm thấy MobileGestalt.plist.")
        }

        if !MobileGestaltBackupManager.shared.hasBackup {
            onLogUpdate("[MG] Đang backup pristine...")
            let originalData = try Data(contentsOf: mgURL)
            guard (try? PropertyListSerialization.propertyList(from: originalData, format: nil)) != nil else {
                throw mgError(-3, "File gốc không parse được — dừng để tránh bootloop.")
            }
            try MobileGestaltBackupManager.shared.ensureBackup(from: originalData)
            onLogUpdate("[MG] ✅ Đã backup pristine.")
        }

        onLogUpdate("[MG] Đang serialize plist...")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: store.mgCurrentDict, format: .binary, options: 0
        )
        
        onLogUpdate("[MG] Đang xin quyền ghi (Native WorseQuery)...")
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              let group = entitlements.first else {
            throw mgError(-5, "Không tìm thấy App Group!")
        }
        
        let handle = NativeWorseQuery.shared.grantAccess(appGroupID: group)
        guard handle > 0 else {
            throw mgError(-5, "Xin quyền MCM thất bại. Hãy chắc chắn cert có App Group hợp lệ.")
        }
        onLogUpdate("[MG] ✅ Đã được cấp quyền ghi.")
        
        defer { NativeWorseQuery.shared.releaseAll() }

        // Gỡ cờ immutable
        var st = stat()
        if stat(onDeviceMGPath, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
            _ = chflags(onDeviceMGPath, st.st_flags & ~UInt32(UF_IMMUTABLE))
        }

        onLogUpdate("[MG] Đang ghi đè MobileGestalt.plist (In-place)...")
        let fd = open(onDeviceMGPath, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else {
            throw mgError(-6, "Mở file thất bại (errno: \(errno))")
        }
        defer { close(fd) }

        let bytesWritten = plistData.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
        guard bytesWritten == plistData.count else {
            throw mgError(-6, "Ghi file thất bại (errno: \(errno))")
        }

        _ = fcntl(fd, F_FULLFSYNC)

        onLogUpdate("[MG] Verify file sau khi ghi...")
        do {
            let writtenData = try Data(contentsOf: mgURL)
            guard let writtenDict = try PropertyListSerialization.propertyList(from: writtenData, format: nil) as? NSDictionary,
                  writtenDict["CacheExtra"] != nil || writtenDict["CacheData"] != nil else {
                throw mgError(-7, "File sau khi ghi không hợp lệ.")
            }
        } catch {
            onLogUpdate("[MG] ⚠️ Verify thất bại — rollback...")
            let pristineData = try MobileGestaltBackupManager.shared.restoreData()
            try? pristineData.write(to: mgURL)
            throw mgError(-8, "File sau khi ghi corrupt, đã rollback: \(error.localizedDescription)")
        }

        onLogUpdate("[MG] ✅ MobileGestalt đã apply thành công. Respring để thay đổi.")
    }

    private static func mgError(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "MobileGestalt", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}