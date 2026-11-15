import Foundation
import AirliftFFI
import Network
import UIKit
import AVFoundation

@MainActor
class OnDevicePairingManager: NSObject, ObservableObject {
    @Published var isPairing = false
    @Published var pin: String = ""
    @Published var statusLog: [String] = []
    @Published var isSuccess = false
    
    private var netService: NetService?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isCancelled = false
    
    // Audio player để giữ app chạy ngầm vô hạn
    private var audioPlayer: AVAudioPlayer?
    
    override init() { super.init() }
    
    func startPairing() {
        guard #available(iOS 27.0, *) else {
            statusLog.append("❌ Chỉ hỗ trợ Pair On Device trên iOS 27 trở lên.")
            return
        }
        guard !isPairing else { return }
        
        isPairing = true
        isCancelled = false
        pin = ""
        statusLog = ["Đang khởi tạo tiến trình Pairing..."]
        isSuccess = false
        
        // 1. Kích hoạt chế độ chạy ngầm vô hạn bằng âm thanh
        activateBackgroundAudio()
        
        // 2. Cấp quyền chạy ngầm tạm thời (fallback)
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.stopPairing()
        }
        
        triggerLocalNetworkPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.statusLog.append("❌ Quyền Local Network bị từ chối.")
                    self.isPairing = false
                }
                return
            }
            
            // Chạy hàm C trên Thread riêng
            let thread = Thread {
                self.runAirliftPairing()
            }
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }
    
    // Kích hoạt âm thanh im lặng để giữ app không bị suspend
    private func activateBackgroundAudio() {
        do {
            // Tạo file âm thanh im lặng tạm thời trong bộ nhớ
            let silentData = Data(count: 44100 * 2) // 1 giây audio 16-bit
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("silent.wav")
            try silentData.write(to: tempURL)
            
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.numberOfLoops = -1 // Lặp vô hạn
            audioPlayer?.volume = 0.0 // Không phát ra tiếng
            audioPlayer?.play()
            
            statusLog.append("🔊 Đã bật chế độ chạy ngầm (Audio Silent).")
        } catch {
            statusLog.append("⚠️ Không thể bật chạy ngầm: \(error.localizedDescription)")
        }
    }
    
    private func stopBackgroundAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    private func triggerLocalNetworkPermission(completion: @escaping (Bool) -> Void) {
        let browser = NWBrowser(for: .bonjour(type: "_remotepairing-pairable-host._tcp", domain: nil), using: .init())
        var finished = false
        
        browser.stateUpdateHandler = { state in
            guard !finished else { return }
            switch state {
            case .ready:
                finished = true
                browser.cancel()
                DispatchQueue.main.async { completion(true) }
            case .failed:
                finished = true
                browser.cancel()
                DispatchQueue.main.async { completion(false) }
            default:
                break
            }
        }
        browser.start(queue: .global(qos: .background))
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            guard !finished else { return }
            finished = true
            browser.cancel()
            DispatchQueue.main.async { completion(true) }
        }
    }
    
    nonisolated private func runAirliftPairing() {
        let outPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        let readyCb: ALPairReadyCb = { ctx, serviceIdPtr, port, txtKeysPtr, txtValsPtr, txtCount in
            guard let ctx = ctx, let serviceIdPtr = serviceIdPtr else { return }
            let manager = Unmanaged<OnDevicePairingManager>.fromOpaque(ctx).takeUnretainedValue()
            let serviceId = String(cString: serviceIdPtr)
            
            var txtDict: [String: Data] = [:]
            if let txtKeysPtr = txtKeysPtr, let txtValsPtr = txtValsPtr {
                for i in 0..<Int(txtCount) {
                    if let keyPtr = txtKeysPtr[i], let valPtr = txtValsPtr[i] {
                        txtDict[String(cString: keyPtr)] = String(cString: valPtr).data(using: .utf8)
                    }
                }
            }
            let txtData = NetService.data(fromTXTRecord: txtDict)
            
            DispatchQueue.main.async {
                manager.advertiseBonjour(serviceId: serviceId, port: port, txtData: txtData)
            }
        }
        
        let pinCb: ALPairPinCb = { pinPtr, ctx in
            guard let ctx = ctx, let pinPtr = pinPtr else { return }
            let manager = Unmanaged<OnDevicePairingManager>.fromOpaque(ctx).takeUnretainedValue()
            let pin = String(cString: pinPtr)
            
            DispatchQueue.main.async {
                manager.pin = pin
                manager.statusLog.append("🔑 Mã PIN: \(pin) — hãy nhập vào Settings.")
            }
        }
        
        var result = ALPairResult()
        let rc = "0.0.0.0".withCString { bindAddr in
            "EnsWilde".withCString { name in
                "iPhone".withCString { model in
                    outPath.withCString { outPathPtr in
                        al_pairing_run_host(bindAddr, 0, name, model, outPathPtr, nil, readyCb, pinCb, context, &result)
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            if rc != 0 || result.error != nil {
                let msg = result.error != nil ? String(cString: result.error!) : "Mã lỗi C: \(rc)"
                self.statusLog.append("❌ Pairing thất bại: \(msg)")
            } else {
                self.statusLog.append("✅ Pairing thành công! Đã lưu file.")
                self.isSuccess = true
                UserDefaults.standard.set("pairingFile.plist", forKey: "PairingFile")
            }
            al_pairing_result_free(&result)
            self.stopPairing()
        }
    }
    
    @MainActor
    private func advertiseBonjour(serviceId: String, port: UInt16, txtData: Data) {
        statusLog.append("Đang quảng bá Bonjour: \(serviceId) (Port \(port))")
        
        // SỬA LỖI 48: Bỏ option .listenForConnections vì al_pairing_run_host đã lắng nghe trên cổng này rồi
        netService = NetService(domain: "local.", type: "_remotepairing-pairable-host._tcp.", name: serviceId, port: Int32(port))
        netService?.delegate = self
        netService?.setTXTRecord(txtData)
        netService?.publish() // Chỉ quảng bá, không mở socket trùng
    }
    
    func stopPairing() {
        isCancelled = true
        netService?.stop()
        netService = nil
        
        stopBackgroundAudio()
        
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        isPairing = false
    }
}

extension OnDevicePairingManager: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        statusLog.append("✅ Đã phát sóng Bonjour. Hãy vào Settings ngay!")
    }
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        statusLog.append("❌ Lỗi Bonjour: \(errorDict)")
    }
}