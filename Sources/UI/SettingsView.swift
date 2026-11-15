import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Network
import AirliftFFI
import Darwin
import Security
import XPC

// MARK: - Private Security Framework APIs
@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(_ allocator: UnsafeRawPointer?) -> CFTypeRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(
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
private func fsgetpath(_ buf: UnsafeMutablePointer<CChar>, _ buflen: Int, _ fsid: UnsafePointer<fsid_t>, _ objid: UInt64) -> Int

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

    init() {
        loadMCM()
    }

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

    private func getPathFromInode(_ inode: UInt64, volumePath: String = "/private/var") -> String? {
        var sfs = statfs()
        if statfs(volumePath, &sfs) != 0 { return nil }
        var fsid = sfs.f_fsid

        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let result = pathBuffer.withUnsafeMutableBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return fsgetpath(base, Int(PATH_MAX), &fsid, inode)
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
            if stat(fullPath, &st) == 0 { inodes.append(st.st_ino) }
        }
        return inodes
    }

    func grantAccess(targetPath: String, appGroupID: String) -> (Int64, String) {
        guard let create = queryCreate, let setClass = querySetClass, let setGroupIds = querySetGroupIds,
              let setFlags = querySetFlags, let setPart = querySetPart, let getResult = queryGetSingleResult,
              let qFree = queryFree, let copyToken = copySandboxToken, let consume = sandboxConsume,
              let strCreate = xpcStringCreate, let xpcRel = xpcRelease else {
            return (-1, "Không load được MCM APIs")
        }

        let fm = FileManager.default
        guard let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return (-1, "Không lấy được App Group URL cho \(appGroupID)")
        }

        let cachesPath = groupURL.appendingPathComponent("Library/Caches").path
        let libPath = groupURL.appendingPathComponent("Library").path
        let backupCaches = groupURL.appendingPathComponent("Library/Caches.bqtool").path

        try? fm.createDirectory(atPath: libPath, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: backupCaches)
        if fm.fileExists(atPath: cachesPath) { try? fm.moveItem(atPath: cachesPath, toPath: backupCaches) }

        do {
            try fm.createSymbolicLink(atPath: cachesPath, withDestinationPath: targetPath)
        } catch {
            return (-1, "Tạo symlink thất bại: \(error.localizedDescription)")
        }

        guard let query = create() else {
            cleanup(cachesPath, backupCaches)
            return (-2, "Tạo query thất bại")
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
            qFree(query)
            xpcRel(ident)
            cleanup(cachesPath, backupCaches)
            return (-3, "XPC Error: containermanagerd từ chối cấp token.")
        }

        guard let tokenPtr = copyToken(result) else {
            qFree(query)
            xpcRel(ident)
            cleanup(cachesPath, backupCaches)
            return (-4, "Kernel từ chối cấp token")
        }

        let consumed = consume(tokenPtr)
        free(tokenPtr)
        qFree(query)
        xpcRel(ident)
        cleanup(cachesPath, backupCaches)

        if consumed < 0 { return (-5, "Consume token thất bại (errno: \(errno))") }

        activeHandles.append(consumed)
        return (consumed, "Thành công qua MCM Symlink")
    }

    func grantViaFsgetpath(targetFile: String) -> (Int64, String) {
        let targetDir = (targetFile as NSString).deletingLastPathComponent
        let inodes = scanInodes(in: targetDir)

        let wq = WorseQuery()
        for inode in inodes {
            guard let realPath = getPathFromInode(inode) else { continue }
            let (granted, handle, _) = wq.grantAccess(atPath: realPath)
            if granted, handle > 0 {
                let res = consumeToken(handle: handle)
                if res.0 > 0 { return (res.0, "Thành công qua fsgetpath: \(realPath)") }
            }
        }
        return (-1, "fsgetpath thất bại")
    }

    private func consumeToken(handle: Int64) -> (Int64, String) {
        guard let tokenPtr = UnsafePointer<CChar>(bitPattern: UInt(handle)) else { return (-1, "Pointer error") }
        let consumed = sandboxConsume?(tokenPtr) ?? -1
        if consumed < 0 { return (-1, "Consume errno: \(errno)") }
        activeHandles.append(consumed)
        return (consumed, "OK")
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
    
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"
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
            runTestSection
            respringSection // NÚT RESPRING
            connectionStatusSection
            pairingFileSection
            languageSection
            accentColorSection
            appInfoSection
        }
        .navigationTitle(L("nav_settings"))
        .onAppear { startMonitoringVPN() }
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
        .alert(L("pairing_error_title"), isPresented: $showErrorAlert) {
            Button(L("alert_ok"), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Extracted Sections

    private var runTestSection: some View {
        Section(header: Text("RUN TEST (WorseQuery Access)")) {
            Button(action: runMobileGestaltTest) {
                HStack {
                    Label("Test MobileGestalt read/write permissions", systemImage: "doc.badge.plus")
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
    }

    private var respringSection: some View {
        Section(header: Text("RESPRING (NeoSpring)")) {
            Button {
                do {
                    try RespringHelper.respring()
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.blue)
                    Text("Respring Device")
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var connectionStatusSection: some View {
        Section(header: Text(L("connection_status"))) {
            statusRow(title: L("pairing_file"), subtitle: pairingFile != nil ? L("status_ready") : L("status_not_ready"), ok: pairingFile != nil)
            statusRow(title: "Tunnel Connection", subtitle: vpnActive ? L("status_ready") : L("status_not_ready"), ok: vpnActive)
            if isAirLiftMode { statusRow(title: L("airlift_mode"), subtitle: L("enabled"), ok: true) }
        }
    }

    private var pairingFileSection: some View {
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
    }

    private var languageSection: some View {
        Section(header: Text(L("settings_language"))) {
            NavigationLink(destination: LanguageSettingsView()) {
                Label(L("settings_language"), systemImage: "globe")
            }
        }
    }

    private var accentColorSection: some View {
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
    }

    private var appInfoSection: some View {
        Section(header: Text(L("settings_app_info"))) {
            HStack { Label("EnsWilde", systemImage: "sparkles"); Spacer(); Text("v3.1.3 Beta 2").font(.footnote).foregroundStyle(.secondary) }
            HStack { Label(L("app_ios"), systemImage: "iphone"); Spacer(); Text(UIDevice.current.systemVersion).font(.footnote).foregroundStyle(.secondary) }
            HStack { Label(L("app_device"), systemImage: "apps.iphone"); Spacer(); Text(settingsDeviceModelName()).font(.footnote).foregroundStyle(.secondary) }
            Text(L("app_info_footer")).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    // MARK: - Actions & Helpers

    private func runMobileGestaltTest() {
        isTestingWrite = true
        writeTestSuccess = nil
        writeTestLog = "[*] Starting permission test (Native MCM & fsgetpath)...\n"

        let work = DispatchWorkItem {
            let testFile = MobileGestaltApplyTask.onDeviceMGPath
            let bridge = NativeWorseQuery.shared
            let runtimeGroups = self.getAllRuntimeAppGroups()
            let targetDir = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"

            DispatchQueue.main.async { self.writeTestLog += "📱 Runtime Groups: \(runtimeGroups.joined(separator: ", "))\n" }

            var finalHandle: Int64 = -1
            var lastError = ""

            for group in runtimeGroups {
                if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) == nil { continue }

                DispatchQueue.main.async { self.writeTestLog += "[*] Try requesting permission via App Group: \(group)...\n" }

                let (handle, error) = bridge.grantAccess(targetPath: targetDir, appGroupID: group)

                if handle > 0 {
                    finalHandle = handle
                    DispatchQueue.main.async { self.writeTestLog += "✅ Success: \(error)\n" }
                    break
                } else {
                    lastError = error
                    DispatchQueue.main.async { self.writeTestLog += " ⚠️ Failure: \(error)\n" }
                }
            }

            if finalHandle <= 0 {
                DispatchQueue.main.async { self.writeTestLog += "[*] Fallback: Try fsgetpath inode traversal...\n" }
                let (handle, error) = bridge.grantViaFsgetpath(targetFile: testFile)
                if handle > 0 {
                    finalHandle = handle
                    DispatchQueue.main.async { self.writeTestLog += "✅ Success: \(error)\n" }
                } else {
                    lastError = error
                    DispatchQueue.main.async { self.writeTestLog += " ⚠️ Failure: \(error)\n" }
                }
            }

            guard finalHandle > 0 else {
                DispatchQueue.main.async {
                    self.writeTestLog += "\n❌ ALL METHODS HAVE FAILED!\n"
                    self.writeTestLog += "👉 The Final Error: \(lastError)\n"
                    self.writeTestLog += "👉 DIAGNOSE:\n"
                    self.writeTestLog += "   - Fake certificate signing or an XPC-related flaw in the AirliftFFI framework.\n"
                    self.writeTestSuccess = false; self.isTestingWrite = false
                }
                return
            }

            DispatchQueue.main.async { self.writeTestLog += "✅ Token acquired! Testing file writing...\n" }
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
                    self.writeTestLog += "✅ FILE WRITE SUCCESSFULLY!\n"
                    self.writeTestSuccess = true; self.isTestingWrite = false
                }
            } catch {
                bridge.releaseAll()
                DispatchQueue.main.async {
                    self.writeTestLog += "❌ WRITE ERROR: \(error.localizedDescription)\n"
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

    private func startMonitoringVPN() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.vpnActive = path.availableInterfaces.contains { $0.type == .other || $0.name.hasPrefix("utun") || $0.name.hasPrefix("ipsec") }
            }
        }
        monitor?.start(queue: DispatchQueue(label: "VPNMonitor"))
    }

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

// MARK: - About View
struct AboutView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage("EnsWilde.userTintColor") private var userTintColorHex: String = "#ef9f76"

    var body: some View {
        Form {
            aboutHeroSection
            aboutSocialSection
            aboutThanksSection
            aboutTranslatorsSection
        }
        .navigationTitle(L("nav_about"))
        .onAppear {
            if localizationManager.availableLanguages.isEmpty {
                Task { await localizationManager.fetchAvailableLanguages() }
            }
        }
    }

    private var aboutHeroSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.system(size: 32)).foregroundStyle(.pink)
                Text(L("about_desc")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: "https://dangdi.dev/donate") { UIApplication.shared.open(url) }
                } label: {
                    Text(L("button_donate"))
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: userTintColorHex))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSocialSection: some View {
        Section {
            Button(action: { if let url = URL(string: "https://t.me/yangjiiidibo") { UIApplication.shared.open(url) } }) {
                Label(L("about_group_yang"), systemImage: "safari")
            }
            Button(action: { if let url = URL(string: "https://t.me/lsnguyengr") { UIApplication.shared.open(url) } }) {
                Label(L("about_group_ls"), systemImage: "safari")
            }
            Button(action: { if let url = URL(string: "https://t.me/lsnguyyniu") { UIApplication.shared.open(url) } }) {
                Label(L("about_contact"), systemImage: "paperplane.fill")
            }
        }
    }

    private var aboutThanksSection: some View {
        Section(header: Text(L("settings_thanks_to"))) {
            creditRow(name: "@YangJiii", desc: "For supporting me during development")
            creditRow(name: "@YangJiii", desc: "Original developer of EnsWilde")
            creditRow(name: "@LSNguyen", desc: "Developer of new EnsWilde")
            creditRow(name: "@forcequitOS", desc: "Bad_query exploit")
            creditRow(name: "@0xjohnnydev", desc: "Airlift exploit")
            creditRow(name: "@mak5er", desc: "Airlift-On-Device")
            creditRow(name: "@jailbreakdotparty", desc: "Config tweak , new logic mobilegestalt")
            creditRow(name: "@LikePass888", desc: "Disable Call Recording Sound (iOS 27)")
            creditRow(name: "@Little_34306", desc: "Original concept of disable call recording sound")
            creditRow(name: "@YiHoooong", desc: "For the silent tone assets and replacement research.")
            creditRow(name: "@Kianuni", desc: "Erosion-cn Developer - Write & Revert tweaks logic")
            creditRow(name: "@Cộng đồng LSNguyen & YangJiii và những người bạn chat ⚡️", desc: "For support my project.")
        }
    }

    private var aboutTranslatorsSection: some View {
        Section(header: Text(L("settings_translators"))) {
            ForEach(translatorLanguages) { langInfo in
                creditRow(name: langInfo.translator ?? "", desc: "\(langInfo.nativeName) (\(langInfo.name)) translation")
            }
        }
    }

    private var translatorLanguages: [LanguageInfo] {
        localizationManager.availableLanguages.filter { (info: LanguageInfo) -> Bool in
            guard let tr = info.translator else { return false }
            return !tr.isEmpty
        }
    }

    @ViewBuilder
    private func creditRow(name: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}