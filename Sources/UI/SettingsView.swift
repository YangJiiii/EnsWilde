import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network
import AirliftFFI
import Darwin
import Security

// MARK: - Private Security Framework APIs
@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelf(_ allocator: UnsafeRawPointer?) -> CFTypeRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlement(
    _ task: CFTypeRef,
    _ entitlement: CFString,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> CFTypeRef?

// MARK: - Private Sandbox & File APIs
@_silgen_name("sandbox_extension_consume")
private func sandbox_extension_consume(_ token: UnsafePointer<CChar>) -> Int64

@_silgen_name("sandbox_extension_release")
private func sandbox_extension_release(_ handle: Int64) -> Int

@_silgen_name("fsgetpath")
private func fsgetpath(_ buf: UnsafeMutablePointer<CChar>, _ buflen: Int, _ fsid: UnsafePointer<CChar>, _ objid: UInt64) -> Int

// MARK: - WorseQuery Bridge (fsgetpath & Fallback)
final class WorseQueryBridge {
    static let shared = WorseQueryBridge()
    private var activeHandles: [Int64] = []
    
    private func getPathFromInode(_ inode: UInt64, volumePath: String = "/private/var") -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = pathBuffer.withUnsafeMutableBufferPointer { buffer in
            fsgetpath(buffer.baseAddress, Int(PATH_MAX), volumePath, inode)
        }
        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }
    
    private func scanInodes(in directory: String) -> [UInt64] {
        var inodes: [UInt64] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }
        for case let path as String in enumerator {
            let fullPath = (directory as NSString).appendingPathComponent(path)
            var st = stat()
            if stat(fullPath, &st) == 0 {
                inodes.append(st.st_ino)
            }
        }
        return inodes
    }
    
    func grantAccessToMobileGestalt(appGroupID: String) -> (Int64, String) {
        let fm = FileManager.default
        guard let appGroupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return (-1, "Không lấy được App Group container")
        }
        let cachesPath = appGroupURL.appendingPathComponent("Library/Caches").path
        let targetDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let testFile = MobileGestaltApplyTask.onDeviceMGPath

        // 1. Thử symlink
        try? fm.removeItem(atPath: cachesPath)
        try? fm.createSymbolicLink(atPath: cachesPath, withDestinationPath: targetDir)

        let wq = WorseQuery()
        let (granted, handleSymlink, errorSymlink) = wq.grantAccess(atPath: cachesPath)
        try? fm.removeItem(atPath: cachesPath)

        if granted, handleSymlink > 0 {
            return consumeToken(handle: handleSymlink)
        }

        // 2. Thử fsgetpath
        let parentDir = (testFile as NSString).deletingLastPathComponent
        let inodes = scanInodes(in: parentDir)
        for inode in inodes {
            guard let realPath = getPathFromInode(inode) else { continue }
            let (granted2, handle2, _) = wq.grantAccess(atPath: realPath)
            if granted2, handle2 > 0 {
                return consumeToken(handle: handle2)
            }
        }

        // 3. Thử trực tiếp trên file
        let (granted3, handle3, error3) = wq.grantAccess(atPath: testFile)
        if granted3, handle3 > 0 {
            return consumeToken(handle: handle3)
        }

        return (-1, "Tất cả thất bại. Lỗi: \(error3.isEmpty ? errorSymlink : error3)")
    }

    private func consumeToken(handle: Int64) -> (Int64, String) {
        guard let tokenPtr = UnsafePointer<CChar>(bitPattern: UInt(handle)) else {
            return (-1, "Pointer error")
        }
        let consumed = sandbox_extension_consume(tokenPtr)
        if consumed < 0 { return (-1, "Consume errno: \(errno)") }
        activeHandles.append(consumed)
        return (consumed, "OK")
    }

    func releaseAll() {
        for h in activeHandles { _ = sandbox_extension_release(h) }
        activeHandles.removeAll()
    }
}

// MARK: - Document Picker
struct DocumentPickerView: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType] = [.data, .item]
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        init(_ parent: DocumentPickerView) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
            parent.onPick(url)
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.dismiss() }
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var toolStore: ToolStore
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("PairingFile") private var pairingFile: String?
    @State private var showPairingPicker = false
    @State private var showOnDevicePairing = false
    @State private var vpnActive: Bool = false
    @State private var monitor: NWPathMonitor?
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false
    @State private var hasBackup: Bool = false
    @State private var backupInfo: MobileGestaltBackupManager.BackupInfo?
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
    @State private var showImportBackupPicker = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    @State private var isTestingWrite = false
    @State private var writeTestLog = ""
    @State private var writeTestSuccess: Bool? = nil

    private var tintOptions: [(name: String, hex: String)] {
        [
            (L("color_orange"), "#ef9f76"),
            (L("color_pink"),   "#f4b8e4"),
            (L("color_mauve"),  "#ca9ee6"),
            (L("color_red"),    "#e78284"),
            (L("color_green"),  "#a6d189"),
            (L("color_blue"),   "#8caaee"),
        ]
    }

    var body: some View {
        Form {
            Section(header: Text("RUN TEST (WorseQuery Access)")) {
                Button(action: runMobileGestaltTest) {
                    HStack {
                        Label("Test quyền đọc/ghi MobileGestalt", systemImage: "doc.badge.plus")
                            .foregroundStyle(.primary)
                        Spacer()
                        if isTestingWrite { ProgressView() }
                    }
                }
                .disabled(isTestingWrite)

                if !writeTestLog.isEmpty {
                    ScrollView {
                        Text(writeTestLog)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(writeTestSuccess == true ? .green : (writeTestSuccess == false ? .red : .primary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 250)
                }
            }

            Section(header: Text(L("connection_status"))) {
                statusRow(title: L("pairing_file"), subtitle: pairingFile != nil ? L("status_ready") : L("status_not_ready"), ok: pairingFile != nil)
                statusRow(title: "LocalDevVPN", subtitle: vpnActive ? L("status_ready") : L("status_not_ready"), ok: vpnActive)
                if isAirLiftMode { statusRow(title: L("airlift_mode"), subtitle: L("enabled"), ok: true) }
            }

            Section(header: Text(L("pairing_file"))) {
                if pairingFile != nil {
                    Button(role: .destructive) {
                        pairingFile = nil
                        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                    } label: { Label(L("button_reset_pairing"), systemImage: "trash") }
                } else {
                    Button { showPairingPicker = true } label: { Label(L("import_pairing"), systemImage: "doc.badge.plus") }

                    if #available(iOS 27.0, *) {
                        Button { showOnDevicePairing = true } label: {
                            Label(L("pair_on_device"), systemImage: "iphone.radiowaves.left.and.right")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section(header: Text(L("backup_section_header"))) {
                if hasBackup, let info = backupInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                            Text(L("backup_available")).font(.subheadline.bold())
                            Spacer()
                        }
                        Text("\(L("backup_date")) \(info.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Text("\(L("backup_size")) \(info.byteCount) bytes").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("backup_none")).font(.subheadline.bold())
                            Text(L("backup_none_desc")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }

                Button { createBackupNow() } label: {
                    Label(L("backup_now"), systemImage: "square.and.arrow.down").foregroundStyle(.primary)
                }

                Button { showImportBackupPicker = true } label: {
                    Label(L("backup_import"), systemImage: "square.and.arrow.down").foregroundStyle(.primary)
                }

                if hasBackup {
                    Button(role: .destructive) { deleteBackup() } label: {
                        Label(L("backup_delete"), systemImage: "trash")
                    }
                }
            }

            Section(header: Text(L("settings_language"))) {
                NavigationLink(destination: LanguageSettingsView()) {
                    Label(L("settings_language"), systemImage: "globe")
                }
            }

            Section(header: Text(L("settings_accent_color"))) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(tintOptions, id: \.hex) { option in
                            colorOptionView(option: option)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Section(header: Text(L("settings_app_info"))) {
                HStack { Label("EnsWilde", systemImage: "sparkles"); Spacer(); Text("v\(appVersion)").font(.footnote).foregroundStyle(.secondary) }
                HStack { Label(L("app_ios"), systemImage: "iphone"); Spacer(); Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary) }
                HStack { Label(L("app_device"), systemImage: "apps.iphone"); Spacer(); Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary) }
                Text(L("app_info_footer")).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .navigationTitle(L("nav_settings"))
        .onAppear { startMonitoringVPN(); refreshBackupInfo() }
        .onDisappear { monitor?.cancel() }
        .sheet(isPresented: $showPairingPicker) {
            DocumentPickerView(allowedContentTypes: [.propertyList, UTType(filenameExtension: "mobiledevicepairing") ?? .data]) { url in handlePairingImport(url) }
        }
        .sheet(isPresented: $showOnDevicePairing) {
            NavigationStack {
                OnDevicePairingView().toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("alert_close")) { showOnDevicePairing = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showImportBackupPicker) {
            DocumentPickerView(allowedContentTypes: [.data, .item]) { url in handleBackupImport(url) }
        }
        .alert(L("pairing_error_title"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func runMobileGestaltTest() {
        isTestingWrite = true
        writeTestSuccess = nil
        writeTestLog = "[*] Bắt đầu quét toàn diện (fsgetpath)...\n"

        let work = DispatchWorkItem {
            let testFile = MobileGestaltApplyTask.onDeviceMGPath
            let bridge = WorseQueryBridge.shared

            if !self.vpnActive {
                DispatchQueue.main.async {
                    self.writeTestLog += "❌ VPN CHƯA BẬT! Bật LocalDevVPN lên boss man.\n"
                    self.writeTestSuccess = false; self.isTestingWrite = false
                }
                return
            }

            let runtimeGroups = self.getAllRuntimeAppGroups()
            DispatchQueue.main.async { self.writeTestLog += "📱 Runtime Groups: \(runtimeGroups.joined(separator: ", "))\n" }

            var finalHandle: Int64 = -1
            var lastError = ""

            for group in runtimeGroups {
                if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) == nil { continue }
                
                DispatchQueue.main.async { self.writeTestLog += "[*] Thử xin quyền qua group: \(group)...\n" }
                let (handle, error) = bridge.grantAccessToMobileGestalt(appGroupID: group)
                
                if handle > 0 {
                    finalHandle = handle
                    DispatchQueue.main.async { self.writeTestLog += "✅ Thành công với group: \(group)!\n" }
                    break
                } else {
                    lastError = error
                    DispatchQueue.main.async { self.writeTestLog += " ⚠️ Thất bại: \(error)\n" }
                }
            }

            guard finalHandle > 0 else {
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ TẤT CẢ PHƯƠNG PHÁP ĐỀU THẤT BẠI!\n"
                    self.writeTestLog += "👉 Lỗi cuối cùng: \(lastError)\n"
                    self.writeTestLog += "👉 CHẨN ĐOÁN:\n"
                    self.writeTestLog += "   - Thằng containermanagerd nó chặn XPC. Dùng cert free của Sideloader hay bị bóp lắm.\n"
                    self.writeTestSuccess = false; self.isTestingWrite = false
                }
                return
            }

            DispatchQueue.main.async { self.writeTestLog += "✅ Đã có token! Đang test ghi file...\n" }
            do {
                let originalData = try Data(contentsOf: URL(fileURLWithPath: testFile))
                var st = stat()
                if stat(testFile, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
                    _ = chflags(testFile, st.st_flags & ~UInt32(UF_IMMUTABLE))
                }
                
                let fd = open(testFile, O_RDWR | O_CLOEXEC)
                guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                defer { close(fd) }
                
                let bytesWritten = originalData.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
                guard bytesWritten == originalData.count else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "pwrite errno: \(errno)"])
                }
                
                _ = fcntl(fd, F_FULLFSYNC)
                bridge.releaseAll()
                DispatchQueue.main.async {
                    self.writeTestLog += "✅ GHI FILE THÀNH CÔNG!\n"
                    self.writeTestSuccess = true; self.isTestingWrite = false
                }
            } catch {
                bridge.releaseAll()
                DispatchQueue.main.async {
                    self.writeTestLog += "❌ LỖI GHI: \(error.localizedDescription)\n"
                    self.writeTestSuccess = false; self.isTestingWrite = false
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func getAllRuntimeAppGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        guard let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) else { return [] }
        return (entitlements as? [String]) ?? []
    }

    @ViewBuilder private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack { Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red); Spacer(); Text(subtitle).font(.caption).foregroundStyle(ok ? .green : .red) }
    }

    @ViewBuilder private func colorOptionView(option: (name: String, hex: String)) -> some View {
        let color = Color(hex: option.hex)
        let isSelected = userTintColorHex.lowercased() == option.hex.lowercased()
        VStack(spacing: 6) {
            Circle().fill(color).frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white).opacity(isSelected ? 1 : 0))
            Text(option.name).font(.caption).foregroundColor(isSelected ? .primary : .secondary)
        }
        .onTapGesture {
            userTintColorHex = option.hex
            let uiColor = UIColor(Color(hex: option.hex))
            UITabBar.appearance().tintColor = uiColor
            UINavigationBar.appearance().tintColor = uiColor
        }
    }

    private func handlePairingImport(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try RPPairingParser.parse(url: url)
            let data = try Data(contentsOf: url)
            let destURL = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            try data.write(to: destURL)
            pairingFile = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func handleBackupImport(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
            do { try MobileGestaltBackupManager.shared.importBackup(from: data); refreshBackupInfo() } catch { print("Failed to import backup: \(error)") }
        }
    }

    private func refreshBackupInfo() {
        hasBackup = MobileGestaltBackupManager.shared.hasBackup
        backupInfo = MobileGestaltBackupManager.shared.info
    }

    private func createBackupNow() {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: MobileGestaltApplyTask.onDeviceMGPath))
            _ = try MobileGestaltBackupManager.shared.ensureBackup(from: data)
            refreshBackupInfo()
        } catch { print("Backup failed") }
    }

    private func deleteBackup() {
        try? MobileGestaltBackupManager.shared.clearBackup()
        refreshBackupInfo()
    }

    private func startMonitoringVPN() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.vpnActive = path.availableInterfaces.contains { $0.type == .other || $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") }
            }
        }
        monitor?.start(queue: DispatchQueue(label: "VPNMonitor"))
    }

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private func settingsDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return "\(UIDevice.current.model) (\(identifier))"
    }
}