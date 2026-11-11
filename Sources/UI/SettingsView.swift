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

// MARK: - Private Sandbox APIs
@_silgen_name("sandbox_extension_consume")
private func sandbox_extension_consume(_ token: UnsafePointer<CChar>) -> Int64

@_silgen_name("sandbox_extension_release")
private func sandbox_extension_release(_ handle: Int64) -> Int

// MARK: - WorseQuery Bridge (Kỹ thuật Symlink Part-Directory - Chuẩn KAMUI)
final class WorseQueryBridge {
    static let shared = WorseQueryBridge()
    private var activeHandles: [Int64] = []
    
    func grantAccessToMobileGestalt(appGroupID: String) -> Int64 {
        let fm = FileManager.default
        
        guard let appGroupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("❌ Không thể lấy App Group container: \(appGroupID)")
            return -1
        }
        
        let cachesPath = appGroupURL.appendingPathComponent("Library/Caches").path
        let libraryPath = appGroupURL.appendingPathComponent("Library").path
        let backupCachesPath = appGroupURL.appendingPathComponent("Library/Caches.bqtool").path
        
        // 1. Backup và xóa Library/Caches hiện tại
        if fm.fileExists(atPath: cachesPath) {
            try? fm.removeItem(atPath: backupCachesPath)
            try? fm.moveItem(atPath: cachesPath, toPath: backupCachesPath)
        }
        
        // 2. Tạo thư mục Library nếu chưa có
        try? fm.createDirectory(atPath: libraryPath, withIntermediateDirectories: true)
        
        // 3. Tạo symlink: Library/Caches -> thư mục MobileGestalt thật
        let targetDir = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        do {
            try fm.createSymbolicLink(atPath: cachesPath, withDestinationPath: targetDir)
        } catch {
            print("❌ Không thể tạo symlink: \(error.localizedDescription)")
            if fm.fileExists(atPath: backupCachesPath) {
                try? fm.moveItem(atPath: backupCachesPath, toPath: cachesPath)
            }
            return -1
        }
        
        // 4. Query WorseQuery để lấy token cho symlink
        let wq = WorseQuery()
        let (granted, handle, errorMsg) = wq.grantAccess(atPath: cachesPath)
        
        guard granted, handle > 0 else {
            print("❌ WorseQuery từ chối grantAccess trên symlink. Error: \(errorMsg)")
            try? fm.removeItem(atPath: cachesPath)
            if fm.fileExists(atPath: backupCachesPath) {
                try? fm.moveItem(atPath: backupCachesPath, toPath: cachesPath)
            }
            return -1
        }
        
        // 5. Consume token
        guard let tokenPtr = UnsafePointer<CChar>(bitPattern: UInt(handle)) else {
            try? fm.removeItem(atPath: cachesPath)
            if fm.fileExists(atPath: backupCachesPath) {
                try? fm.moveItem(atPath: backupCachesPath, toPath: cachesPath)
            }
            return -1
        }
        
        let consumedHandle = sandbox_extension_consume(tokenPtr)
        if consumedHandle < 0 {
            print("⚠️ Consume token thất bại (errno: \(errno))")
            try? fm.removeItem(atPath: cachesPath)
            if fm.fileExists(atPath: backupCachesPath) {
                try? fm.moveItem(atPath: backupCachesPath, toPath: cachesPath)
            }
            return -1
        }
        
        activeHandles.append(consumedHandle)
        
        // 6. Xóa symlink và khôi phục Caches gốc
        try? fm.removeItem(atPath: cachesPath)
        if fm.fileExists(atPath: backupCachesPath) {
            try? fm.moveItem(atPath: backupCachesPath, toPath: cachesPath)
        }
        
        print("✅ Symlink part-directory thành công! Handle: \(consumedHandle)")
        return consumedHandle
    }
    
    func releaseAll() {
        for h in activeHandles {
            _ = sandbox_extension_release(h)
        }
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

    // MARK: - State cho Run Test
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
                        if isTestingWrite {
                            ProgressView()
                        }
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
                    .frame(maxHeight: 150)
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

    // MARK: - Core Run Test Logic (Kỹ thuật Symlink Part-Directory)
    private func runMobileGestaltTest() {
        isTestingWrite = true
        writeTestSuccess = nil
        writeTestLog = "[*] Bắt đầu test quyền (Symlink Part-Directory Protocol)...\n"

        let work = DispatchWorkItem {
            let testFile = MobileGestaltApplyTask.onDeviceMGPath
            let bridge = WorseQueryBridge.shared

            // 1. Lấy App Group (bắt buộc phải có)
            DispatchQueue.main.async { self.writeTestLog += "[*] Đang quét App Group...\n" }
            guard let appGroup = self.getFirstValidAppGroup() else {
                DispatchQueue.main.async {
                    self.writeTestLog += "❌ THẤT BẠI: Không tìm thấy App Group hợp lệ trong chữ ký!\n"
                    self.writeTestLog += "👉 Mày phải sign app với App Group entitlement (vd: group.com.mày.app) thì worse_query mới chạy.\n"
                    self.writeTestLog += "👉 Nếu dùng Feather/ESign, phải dùng profile có App Group, không dùng wildcard.\n"
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                }
                return
            }
            DispatchQueue.main.async { self.writeTestLog += "✅ App Group: \(appGroup)\n" }

            // 2. Xin quyền qua kỹ thuật Symlink Part-Directory
            DispatchQueue.main.async { self.writeTestLog += "[*] Đang tạo symlink part-directory và xin quyền...\n" }
            let handle = bridge.grantAccessToMobileGestalt(appGroupID: appGroup)

            guard handle > 0 else {
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ THẤT BẠI: grantAccess trên symlink trả về handle không hợp lệ.\n"
                    self.writeTestLog += "👉 Nguyên nhân có thể:\n"
                    self.writeTestLog += "  1. App Group chưa được sign đúng (kiểm tra entitlements).\n"
                    self.writeTestLog += "  2. Signer đã drop App Group (dùng AltStore/SideStore để tự tạo).\n"
                    self.writeTestLog += "  3. Profile wildcard (App ID *) không thể chứa App Group.\n"
                    self.writeTestLog += "  4. Framework WorseQuery phiên bản cũ, chưa hỗ trợ iOS 27.2+.\n"
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                }
                return
            }
            DispatchQueue.main.async { self.writeTestLog += "✅ Xin quyền thành công! Handle: \(handle)\n" }

            // 3. Đọc dữ liệu gốc
            DispatchQueue.main.async { self.writeTestLog += "[*] Đang đọc file thật...\n" }
            let originalData: Data
            do {
                originalData = try Data(contentsOf: URL(fileURLWithPath: testFile))
                DispatchQueue.main.async { self.writeTestLog += "✅ Đọc file thành công (\(originalData.count) bytes)!\n" }
            } catch {
                bridge.releaseAll()
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ LỖI ĐỌC FILE: \(error.localizedDescription)\n"
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                }
                return
            }

            // 4. Gỡ cờ bất biến (UF_IMMUTABLE) nếu có
            var st = stat()
            if stat(testFile, &st) == 0, (st.st_flags & UInt32(UF_IMMUTABLE)) != 0 {
                if chflags(testFile, st.st_flags & ~UInt32(UF_IMMUTABLE)) == 0 {
                    DispatchQueue.main.async { self.writeTestLog += "✅ Đã gỡ cờ UF_IMMUTABLE!\n" }
                } else {
                    DispatchQueue.main.async { self.writeTestLog += "⚠️ Không thể gỡ cờ UF_IMMUTABLE (errno: \(errno))\n" }
                }
            }

            // 5. GHI FILE (In-place Overwrite, chuẩn Erosion-CN)
            DispatchQueue.main.async { self.writeTestLog += "[*] Đang thử ghi đè tại chỗ (pwrite với O_RDWR)...\n" }
            do {
                let fd = open(testFile, O_RDWR | O_CLOEXEC)
                guard fd >= 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                                  userInfo: [NSLocalizedDescriptionKey: "Không thể mở file để ghi. errno: \(errno)"])
                }
                defer { close(fd) }

                let bytesWritten = originalData.withUnsafeBytes { buffer in
                    pwrite(fd, buffer.baseAddress, buffer.count, 0)
                }
                guard bytesWritten == originalData.count else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                                  userInfo: [NSLocalizedDescriptionKey: "Ghi file thất bại (pwrite). errno: \(errno)"])
                }

                let fileSize = lseek(fd, 0, SEEK_END)
                if fileSize > off_t(originalData.count) {
                    ftruncate(fd, off_t(originalData.count))
                }

                if fcntl(fd, F_FULLFSYNC) == -1 {
                    DispatchQueue.main.async { self.writeTestLog += "⚠️ F_FULLFSYNC thất bại (errno: \(errno)), nhưng dữ liệu có thể đã ghi.\n" }
                }

                bridge.releaseAll()

                DispatchQueue.main.async {
                    self.writeTestLog += "✅ GHI FILE THÀNH CÔNG!\n"
                    self.writeTestLog += "🎉 App Group & WorseQuery hoạt động hoàn hảo!\nBạn có thể dùng Apply bình thường."
                    self.writeTestSuccess = true
                    self.isTestingWrite = false
                }
            } catch {
                bridge.releaseAll()
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ LỖI GHI FILE: \(error.localizedDescription)\n\n"
                    self.writeTestLog += "👉 Nguyên nhân: Kernel vẫn từ chối ghi dù đã consume token qua symlink.\n"
                    self.writeTestLog += "  1. File có thể đang bị lock bởi daemon khác.\n"
                    self.writeTestLog += "  2. Sandbox token không có quyền recursive.\n"
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    // Hàm lấy App Group xịn nhất (đọc runtime entitlements)
    private func getFirstValidAppGroup() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        guard let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) else { return nil }
        guard let groups = entitlements as? [String] else { return nil }

        let fm = FileManager.default
        for g in groups {
            if fm.containerURL(forSecurityApplicationGroupIdentifier: g) != nil {
                return g
            }
        }
        return groups.first
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