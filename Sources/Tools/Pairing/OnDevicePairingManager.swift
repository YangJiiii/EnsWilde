//  OnDevicePairingManager.swift
//  EnsWilde

import Foundation
import AirliftFFI
import Network
import UIKit

@MainActor
class OnDevicePairingManager: NSObject, ObservableObject {
    @Published var isPairing = false
    @Published var pin: String = ""
    @Published var statusLog: [String] = []
    @Published var isSuccess = false
    
    private var netService: NetService?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var pairingTask: Task<Void, Never>?
    
    // Khởi tạo NSObject cho NetServiceDelegate
    override init() {
        super.init()
    }
    
    func startPairing() {
        guard #available(iOS 27.0, *) else {
            statusLog.append("❌ Chỉ hỗ trợ Pair On Device trên iOS 27 trở lên.")
            return
        }
        
        guard !isPairing else { return }
        
        isPairing = true
        pin = ""
        statusLog = ["Đang khởi tạo tiến trình Pairing..."]
        isSuccess = false
        
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            self.stopPairing()
        }
        
        pairingTask = Task.detached(priority: .userInitiated) {
            await self.runAirliftPairing()
        }
    }
    
    private func runAirliftPairing() async {
        let outPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        
        // Giữ class trên heap trong suốt quá trình C chạy
        let context = Unmanaged.passRetained(self).toOpaque()
        
        // Callback khi Host sẵn sàng
        let readyCb: ALPairReadyCb = { ctx, serviceIdPtr, port, txtKeysPtr, txtValsPtr, txtCount in
            guard let ctx = ctx, let serviceIdPtr = serviceIdPtr else { return }
            
            let manager = Unmanaged<OnDevicePairingManager>.fromOpaque(ctx).takeUnretainedValue()
            let serviceId = String(cString: serviceIdPtr)
            
            var txtDict: [String: Data] = [:]
            if let txtKeysPtr = txtKeysPtr, let txtValsPtr = txtValsPtr {
                for i in 0..<Int(txtCount) {
                    if let keyPtr = txtKeysPtr[i], let valPtr = txtValsPtr[i] {
                        let key = String(cString: keyPtr)
                        let val = String(cString: valPtr)
                        txtDict[key] = val.data(using: .utf8)
                    }
                }
            }
            let txtData = NetService.data(fromTXTRecord: txtDict)
            
            DispatchQueue.main.async {
                manager.advertiseBonjour(serviceId: serviceId, port: port, txtData: txtData)
            }
        }
        
        // Callback khi có PIN
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
        
        // SỬA LỖI 49: Dùng "0.0.0.0" thay vì "10.7.0.1" để bind vào tất cả interfaces
        let rc = "0.0.0.0".withCString { bindAddr in
            "EnsWilde".withCString { name in
                "iPhone".withCString { model in
                    outPath.withCString { outPathPtr in
                        al_pairing_run_host(
                            bindAddr,
                            0,          // Port 0 = OS tự chọn
                            name,
                            model,
                            outPathPtr,
                            nil,        // host_alt_irk_hex
                            readyCb,
                            pinCb,
                            context,
                            &result
                        )
                    }
                }
            }
        }
        
        // Giải phóng context
        Unmanaged<OnDevicePairingManager>.fromOpaque(context).release()
        
        // Xử lý kết quả trả về
        if rc != 0 || result.error != nil {
            let msg = result.error != nil ? String(cString: result.error!) : "Mã lỗi C: \(rc)"
            DispatchQueue.main.async {
                self.statusLog.append("❌ Pairing thất bại: \(msg)")
            }
            al_pairing_result_free(&result)
        } else {
            DispatchQueue.main.async {
                self.statusLog.append("✅ Pairing thành công! Đã lưu pairingFile.plist.")
                self.isSuccess = true
                UserDefaults.standard.set("pairingFile.plist", forKey: "PairingFile")
            }
            al_pairing_result_free(&result)
        }
        
        DispatchQueue.main.async {
            self.stopPairing()
        }
    }
    
    private func advertiseBonjour(serviceId: String, port: UInt16, txtData: Data) {
        statusLog.append("Đang quảng bá Bonjour: \(serviceId) (Port \(port))")
        netService = NetService(domain: "local.", type: "_remotepairing-pairable-host._tcp.", name: serviceId, port: Int32(port))
        netService?.delegate = self
        netService?.setTXTRecord(txtData)
        netService?.publish()
    }
    
    func stopPairing() {
        netService?.stop()
        netService = nil
        
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
        isPairing = false
        pairingTask?.cancel()
        pairingTask = nil
    }
}

// MARK: - NetServiceDelegate
extension OnDevicePairingManager: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        statusLog.append("✅ Đã phát sóng Bonjour. Hãy vào Settings ngay!")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        statusLog.append("❌ Lỗi phát sóng Bonjour: \(errorDict)")
    }
}