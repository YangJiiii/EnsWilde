import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ZIPFoundation
import AirliftFFI
import Network

struct AppleWalletView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject var walletStore: AppleWalletStore
    @AppStorage("ShowApplyTab") private var showApplyTab: Bool = false
    @State private var showAddSheet = false
    @State private var showScanSheet = false
    @State private var showImportZIPSheet = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isScanning = false
    @State private var showSavedAlert = false

    var body: some View {
        Form {
            Section(header: Text(L("tool_apple_wallet"))) { Toggle(L("wallet_enable"), isOn: $walletStore.appleWalletEnabled) }
            Section(header: Text(L("section_wallet_cards"))) {
                if walletStore.cards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "creditcard").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text(L("wallet_no_cards")).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    ForEach(Array(walletStore.cards.enumerated()), id: \.element.id) { index, card in
                        NavigationLink(destination: AppleWalletCardDetailView(card: card, walletStore: walletStore)) {
                            WalletCardPreview(card: card, index: index, total: walletStore.cards.count, walletStore: walletStore)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section(header: Text(L("section_add_card"))) {
                Button(L("wallet_scan_card")) { showScanSheet = true }
                Button(L("wallet_manual_input")) { showAddSheet = true }
                Button(L("wallet_import_default_zip")) { showImportZIPSheet = true }
            }
            
            Section {
                Button { showApplyTab = true; showSavedAlert = true } label: {
                    HStack { Image(systemName: "square.and.arrow.down"); Text(L("save_changes")).font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }.disabled(!walletStore.appleWalletEnabled)
                
                Button(role: .destructive) {
                    walletStore.cards.removeAll()
                    walletStore.appleWalletEnabled = false
                    walletStore.saveCards()
                } label: {
                    HStack { Image(systemName: "trash"); Text(L("wallet_reset")).font(.headline) }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }
            }
        }
        .headerProminence(.increased)
        .navigationTitle(L("wallet_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) { ManualAddCardSheet(walletStore: walletStore) }
        .sheet(isPresented: $showScanSheet) { ScanCardIDSheet(walletStore: walletStore, isPresented: $showScanSheet) }
        .sheet(isPresented: $showImportZIPSheet) { ImportDefaultCardSheet(walletStore: walletStore) }
        .alert(L("alert_error"), isPresented: $showErrorAlert) { Button(L("alert_ok")) {} } message: { Text(errorMessage) }
        .alert(L("saved_title"), isPresented: $showSavedAlert) { Button(L("alert_ok")) {} } message: { Text(L("saved_message")) }
    }
}

// MARK: - Scan Card Sheet

struct ScanCardIDSheet: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Environment(\.dismiss) var dismiss
    @ObservedObject var walletStore: AppleWalletStore
    @Binding var isPresented: Bool
    @State private var isScanning = false
    @State private var scanStatus = L("wallet_scan_ready")
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("wallet_scan_card"))) {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8).frame(width: 150, height: 150)
                            if isScanning {
                                Circle().trim(from: 0, to: 0.7)
                                    .stroke(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .frame(width: 150, height: 150)
                                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isScanning)
                            }
                            Image(systemName: isScanning ? "wave.3.right.circle.fill" : "creditcard.fill")
                                .font(.system(size: 60)).foregroundStyle(isScanning ? .blue : .secondary)
                        }.frame(maxWidth: .infinity)
                        Text(scanStatus).font(.headline).multilineTextAlignment(.center)
                        if isScanning {
                            Text(L("wallet_scan_time_60s").replacingOccurrences(of: "{time}", with: String(format: "%.0f", elapsedTime)))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(L("wallet_scan_instruction")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }.padding(.vertical, 20)
                }
                Section(header: Text(L("section_actions"))) {
                    if isScanning {
                        Button(L("wallet_scan_cancel")) { cancelScanAndDismiss() }
                    } else {
                        Button(L("wallet_scan_start")) { startScanning() }
                    }
                }
            }
            .navigationTitle(L("wallet_scan_card"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("alert_close")) { cancelScanAndDismiss() } }
            }
            .onDisappear { cancelScan() }
        }
    }

    private func startScanning() {
        guard !isScanning else { return }
        
        guard NetworkStatus.isVPNTunnelPresent() else {
            scanStatus = L("wallet_scan_vpn_required")
            return
        }
        
        let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            scanStatus = L("wallet_scan_pairing_missing")
            return
        }
        
        isScanning = true
        elapsedTime = 0
        scanStatus = L("wallet_scan_scanning")

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                if isScanning { elapsedTime += 1 }
            }
        }

        scanTask?.cancel()
        scanTask = Task { [weak walletStore] in
            do {
                let cardID = try await scanOneWalletCardIDSafe(timeout: 60)
                await MainActor.run {
                    guard isScanning else { return }
                    stopScanningTimerOnly()
                    let newCard = AppleWalletCard(id: cardID, name: "Card \(cardID.prefix(8))")
                    walletStore?.addCard(newCard)
                    scanStatus = L("wallet_scan_success")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                }
            } catch is CancellationError {
                await MainActor.run { stopScanningTimerOnly() }
            } catch {
                await MainActor.run {
                    guard isScanning else { return }
                    stopScanningTimerOnly()
                    scanStatus = L("wallet_scan_error").replacingOccurrences(of: "{error}", with: error.localizedDescription)
                }
            }
        }
    }

    private func cancelScanAndDismiss() {
        cancelScan()
        dismiss()
    }

    private func stopScanningTimerOnly() {
        isScanning = false
        timer?.invalidate()
        timer = nil
    }

    private func cancelScan() {
        stopScanningTimerOnly()
        scanTask?.cancel()
        scanTask = nil
        al_syslog_stream_stop()
    }
}

// MARK: - Airlift Syslog Scanner

private final class SyslogContextBox {
    let onLine: (String) -> Void
    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }
}

func scanOneWalletCardIDSafe(timeout: TimeInterval = 60) async throws -> String {
    let pairingPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
    
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()
            
            func safeResume(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
                al_syslog_stream_stop()
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                safeResume(.failure(NSError(domain: "Scan", code: -2, userInfo: [NSLocalizedDescriptionKey: "Hết thời gian quét (60s)."])))
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let box = SyslogContextBox { line in
                    if line.localizedCaseInsensitiveContains("passd") || line.localizedCaseInsensitiveContains("Cards") {
                        if let cardID = extractWalletCardID(from: line) {
                            safeResume(.success(cardID))
                        }
                    }
                }
                let opaque = Unmanaged.passRetained(box).toOpaque()
                
                let cb: ALSyslogLineCallback = { ctx, msgPtr in
                    guard let ctx = ctx, let msgPtr = msgPtr else { return }
                    let box = Unmanaged<SyslogContextBox>.fromOpaque(ctx).takeUnretainedValue()
                    let line = String(cString: msgPtr)
                    box.onLine(line)
                }
                
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                let res = al_syslog_stream_start(pairingPath, cb, opaque, &errPtr)
                
                if res != 0 {
                    let msg = errPtr != nil ? String(cString: errPtr!) : "Không thể khởi động Syslog qua Airlift."
                    if let e = errPtr { al_string_free(e) }
                    safeResume(.failure(NSError(domain: "Scan", code: Int(res), userInfo: [NSLocalizedDescriptionKey: msg])))
                }
                
                Unmanaged<SyslogContextBox>.fromOpaque(opaque).release()
            }
        }
    } onCancel: {
        al_syslog_stream_stop()
    }
}