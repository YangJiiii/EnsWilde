//  OnDevicePairingManager.swift
//  EnsWilde

import Foundation
import AirliftFFI
import Network
import UIKit

@MainActor
class OnDevicePairingManager: ObservableObject {
    @Published var isPairing = false
    @Published var pin: String = ""
    @Published var statusLog: [String] = []
    @Published var isSuccess = false
    
    private var netService: NetService?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var pairingTask: Task<Void, Never>?
    
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
        let context = Unmanaged.passRetained(self).toOpaque()
        defer { Unmanaged<OnDevicePairingManager>.fromOpaque(context).release() }
        
        var result = ALPairResult()
        
        let readyCb: ALPairReadyCb = { ctx, serviceIdPtr, port, txtKeysPtr, txtValsPtr, txtCount in
            guard let ctx = ctx, let serviceIdPtr = serviceIdPtr else { return }
            let manager = Unmanaged<OnDevicePairingManager>.fromOpaque(ctx).takeUnretainedValue()
            let serviceId = String(cString: serviceIdPtr)
            
            var txtDict: [String: Data] = [:]
            if let txtKeysPtr = txtKeysPtr, let txtValsPtr = txtValsPtr {
                for i in 0..<txtCount {
                    let key = String(cString: txtKeysPtr[i])
                    let val = String(cString: txtValsPtr[i])
                    txtDict[key] = val.data(using: .utf8)
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
        
        let rc = al_pairing_run_host(
            "10.7.0.1", 0, "EnsWilde", "iPhone", outPath, nil,
            readyCb, pinCb, context, &result
        )
        
        if let error = result.error {
            let msg = String(cString: error)
            DispatchQueue.main.async {
                self.statusLog.append("❌ Pairing thất bại: \(msg)")
            }
            al_pairing_result_free(&result)
        } else {
            DispatchQueue.main.async {
                self.statusLog.append("✅ Pairing thành công! Đã lưu pairingFile.plist.")
                self.isSuccess = true
                // Lưu key để SettingsView nhận diện
                UserDefaults.standard.set("pairingFile.plist", forKey: "PairingFile")
            }
            al_pairing_result_free(&result)
        }
        
        DispatchQueue.main.async {
            self.stopPairing()
        }
    }
    
    private func advertiseBonjour(serviceId: String, port: Int32, txtData: Data) {
        statusLog.append("Đang quảng bá Bonjour: \(serviceId) (Port \(port))")
        netService = NetService(domain: "local.", type: "_remotepairing-pairable-host._tcp.", name: serviceId, port: port)
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

extension OnDevicePairingManager: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        statusLog.append("✅ Đã phát sóng Bonjour. Hãy vào Settings ngay!")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        statusLog.append("❌ Lỗi phát sóng Bonjour: \(errorDict)")
    }
}