import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network
import AirliftFFI
import Darwin
import Security // Cần import Security để đọc App Group từ Entitlements

// MARK: - Private Security Framework APIs
// Hai hàm dưới đây là private API của Security.framework (không có trong public header).
// Khai báo @_silgen_name để Swift link tới symbol thật trong framework.
// "Create"/"Copy" ⇒ trả về +1 retained, nên dùng CFTypeRef? để ARC quản lý đúng.

@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelf(_ allocator: UnsafeRawPointer?) -> CFTypeRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlement(
    _ task: CFTypeRef,
    _ entitlement: CFString,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> CFTypeRef?

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
            // MARK: - Run Test Section
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

    // MARK: - Logic Test WQ (Đọc App Group + pwrite + O_RDWR)
    private func runMobileGestaltTest() {
        isTestingWrite = true
        writeTestSuccess = nil
        writeTestLog = "[*] Bắt đầu test quyền...\n"

        let work = DispatchWorkItem {
            let testFile = MobileGestaltApplyTask.onDeviceMGPath

            // 1. Đọc App Group từ Entitlements (Giống Erosion)
            DispatchQueue.main.async { self.writeTestLog += "[*] Đang kiểm tra App Group...\n" }
            if let appGroup = self.getAppGroupFromEntitlements() {
                DispatchQueue.main.async { self.writeTestLog += " (wq) Using app group:\n \(appGroup)\n" }
            } else {
                DispatchQueue.main.async { self.writeTestLog += " ⚠️ Không tìm thấy App Group trong chữ ký!\n" }
            }

            DispatchQueue.main.async { self.writeTestLog += "[*] Khởi tạo WorseQuery...\n" }
            let bq = WorseQuery()

            DispatchQueue.main.async { self.writeTestLog += "[*] Đang xin quyền vào FILE:\n    \(testFile)\n" }
            let (granted, _, errorMsg) = bq.grantAccess(atPath: testFile)

            if !granted {
                let msg = errorMsg.isEmpty ? "Không rõ nguyên nhân" : errorMsg
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ THẤT BẠI: grantAccess trả về false.\nChi tiết: \(msg)\n"
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                }
                return
            }

            DispatchQueue.main.async { self.writeTestLog += "✅ grantAccess thành công!\n" }
            DispatchQueue.main.async { self.writeTestLog += "[*] Đang thử đọc file thật...\n" }

            // Bước 1: Đọc dữ liệu gốc
            let originalData: Data
            do {
                originalData = try Data(contentsOf: URL(fileURLWithPath: testFile))
                DispatchQueue.main.async { self.writeTestLog += "✅ Đọc file thành công (\(originalData.count) bytes)!\n" }
            } catch {
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ LỖI ĐỌC FILE: \(error.localizedDescription)\n"
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                }
                return
            }

            // Bước 2: Ghi đè "tại chỗ" (in-place) bằng pwrite + O_RDWR
            DispatchQueue.main.async { self.writeTestLog += "[*] Đang thử ghi đè tại chỗ (pwrite với O_RDWR)...\n" }
            do {
                // SỬA LỖI EPERM: Dùng O_RDWR thay vì O_WRONLY
                let fd = open(testFile, O_RDWR)
                guard fd >= 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Không thể mở file để ghi. errno: \(errno)"])
                }
                defer { close(fd) }

                // Ghi dữ liệu tại offset 0
                let bytesWritten = originalData.withUnsafeBytes { buffer in
                    pwrite(fd, buffer.baseAddress, buffer.count, 0)
                }
                guard bytesWritten == originalData.count else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Ghi file thất bại. errno: \(errno)"])
                }

                // Đồng bộ hóa dữ liệu xuống đĩa vật lý
                if fcntl(fd, F_FULLFSYNC) == -1 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "F_FULLFSYNC thất bại. errno: \(errno)"])
                }

                DispatchQueue.main.async {
                    self.writeTestLog += "✅ GHI FILE THÀNH CÔNG!\n"
                    self.writeTestLog += "🎉 App Group & WorseQuery hoạt động hoàn hảo!\nBạn có thể dùng Apply bình thường."
                    self.writeTestSuccess = true
                    self.isTestingWrite = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ LỖI GHI FILE: \(error.localizedDescription)\n\n"
                    self.writeTestLog += "👉 Nguyên nhân: Đã dùng O_RDWR nhưng kernel vẫn từ chối. Hãy chắc chắn file không bị lock, và App Group đã được consume đúng cách."
                    self.writeTestSuccess = false
                    self.isTestingWrite = false
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    // Hàm lấy App Group từ Entitlements (Giống Erosion)
    private func getAppGroupFromEntitlements() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        guard let entitlements = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) else { return nil }
        let groups = entitlements as? [String]
        return groups?.first
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