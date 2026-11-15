//
//  WriteHelpers.swift
//  Erosion
//
//  Hardened in-place storage write protocol (Zero 0-byte window + F_FULLFSYNC + automatic rollback).
//

import Foundation
import Darwin

private let fm = FileManager.default

private func fullFsyncSafe(_ fd: Int32) -> Bool {
    if fcntl(fd, F_FULLFSYNC) == 0 {
        return true
    }
    return fsync(fd) == 0
}

func writeFileTemp(_ data: Data, to url: URL) -> (Bool, String) {
    guard !data.isEmpty else {
        return (false, L("拒绝写入 0 字节空数据！"))
    }
    do {
        var statBuf = stat()
        let hasOriginal = (stat(url.path, &statBuf) == 0)

        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: [.withoutOverwriting])
        defer { try? fm.removeItem(at: tempURL) }

        if hasOriginal {
            _ = chmod(tempURL.path, statBuf.st_mode & 0o7777)
            _ = chown(tempURL.path, statBuf.st_uid, statBuf.st_gid)
            let _ = try fm.replaceItemAt(url, withItemAt: tempURL)
            _ = chmod(url.path, statBuf.st_mode & 0o7777)
            _ = chown(url.path, statBuf.st_uid, statBuf.st_gid)
        } else {
            try fm.moveItem(at: tempURL, to: url)
        }

        return (true, "succeeded")
    } catch {
        print("(fm) failed to write file: \(error.localizedDescription)")
        return (false, error.localizedDescription)
    }
}

/// Safe in-place write preserving Inode, ownership, permissions, and xattrs.
/// Overwrites directly via `pwrite` WITHOUT pre-truncating to 0 bytes, truncates tail only after write,
/// flushes physical NAND via `F_FULLFSYNC`, verifies full readback, and rolls back `og` on any failure.
func writeFileAtomically(_ data: Data, to url: URL, allowEmpty: Bool = false) -> (Bool, String) {
    if !allowEmpty && data.isEmpty {
        return (false, L("安全拦截：禁止向目标文件原位写入 0 字节空数据！"))
    }

    guard let og = try? Data(contentsOf: url) else {
        return (false, L("无法读取原文件备份数据，已中止原位写入！"))
    }

    let fd = url.path.withCString {
        open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    }
    guard fd >= 0 else {
        return (false, fileWriteErr.open(errno: errno).localizedDescription)
    }
    defer {
        close(fd)
    }

    do {
        // 1. Overwrite directly from offset 0 via pwrite (NEVER ftruncate to 0 first!)
        try pwriteAll(fd, data, startOffset: 0)

        // 2. Only shrink tail if new payload is shorter than original payload
        if data.count < og.count {
            guard ftruncate(fd, off_t(data.count)) == 0 else {
                throw fileWriteErr.truncate(errno: errno)
            }
        }

        // 3. Flush APFS + NVMe controller cache to physical NAND
        guard fullFsyncSafe(fd) else {
            throw fileWriteErr.sync(errno: errno)
        }

        // 4. Full descriptor readback byte-for-byte verification
        guard lseek(fd, 0, SEEK_SET) == 0 else {
            throw fileWriteErr.verificationFailed
        }
        let verify = try readAll(fd)
        guard verify == data else {
            throw fileWriteErr.verificationFailed
        }
    } catch {
        print("[!] (io) writeFileAtomically failed (\(error)), rolling back \(og.count) original bytes in-place...")
        if (try? pwriteAll(fd, og, startOffset: 0)) != nil {
            _ = ftruncate(fd, off_t(og.count))
            _ = fullFsyncSafe(fd)
        }
        return (false, L("原位写入或物理落盘校验失败，已执行原位回滚：\(error.localizedDescription)"))
    }
    return (true, "succeeded")
}

private enum fileWriteErr: LocalizedError {
    case open(errno: Int32)
    case truncate(errno: Int32)
    case write(errno: Int32)
    case sync(errno: Int32)
    case rollback(errno: Int32)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .open(let e): return L("打开文件描述符失败 (errno=\(e))")
        case .truncate(let e): return L("裁剪文件尾部失败 (errno=\(e))")
        case .write(let e): return L("写入文件块失败 (errno=\(e))")
        case .sync(let e): return L("物理闪存同步 F_FULLFSYNC 失败 (errno=\(e))")
        case .rollback(let e): return L("回滚文件失败 (errno=\(e))")
        case .verificationFailed: return L("写后描述符字节比对不一致")
        }
    }
}

private func readAll(_ fd: Int32) throws -> Data {
    var res = Data()
    var buf = [UInt8](repeating: 0, count: 64 * 1024)

    while true {
        let count = buf.withUnsafeMutableBytes { rawBuffer in
            read(fd, rawBuffer.baseAddress, rawBuffer.count)
        }
        if count > 0 {
            res.append(buf, count: count)
            continue
        }
        if count == 0 {
            return res
        }
        if errno == EINTR {
            continue
        }
        throw fileWriteErr.verificationFailed
    }
}

private func pwriteAll(_ fd: Int32, _ data: Data, startOffset: off_t) throws {
    guard !data.isEmpty else { return }

    try data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else {
            throw fileWriteErr.write(errno: EFAULT)
        }

        var written = 0
        while written < data.count {
            let res = pwrite(
                fd,
                base.advanced(by: written),
                data.count - written,
                startOffset + off_t(written)
            )
            if res > 0 {
                written += res
                continue
            }
            if res < 0 && errno == EINTR {
                continue
            }
            throw fileWriteErr.write(errno: errno)
        }
    }
}