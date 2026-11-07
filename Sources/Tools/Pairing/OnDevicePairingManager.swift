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
        
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.stopPairing()
        }
        
        // Kích hoạt xin quyền Local Network
        triggerLocalNetworkPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.statusLog.append("❌ Quyền Local Network bị từ chối. Vui lòng bật trong Cài đặt > Quyền riêng tư > Mạng cục bộ.")
                    self.isPairing = false
                }
                return
            }
            
            self.pairingTask = Task.detached(priority: .userInitiated) {
                await self.runAirliftPairing()
            }
        }
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
            case .failed(let error):
                finished = true
                browser.cancel()
                DispatchQueue.main.async { completion(false) }
                print("Local Network permission check failed: \(error)")
            default:
                break
            }
        }
        browser.start(queue: .global(qos: .background))
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            guard !finished else { return }
            finished = true
            browser.cancel()
            DispatchQueue.main.async { completion(false) }
        }
    }
    
    private func runAirliftPairing() async {
        let outPath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        let context = Unmanaged.passRetained(self).toOpaque()
        
        // KHÔNG DÙNG [weak self] TRONG C CLOSURE
        let readyCb: ALPairReadyCb = { ctx, serviceIdPtr, port, txtKeysPtr, txtValsPtr, txtCount in
            guard let ctx = ctx, let serviceIdPtr = serviceIdPtr else { return }
            
            // Lấy lại instance từ ctx
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
                        al_pairing_run_host(
                            bindAddr,
                            0,
                            name,
                            model,
                            outPathPtr,
                            nil,
                            readyCb,
                            pinCb,
                            context,
                            &result
                        )
                    }
                }
            }
        }
        
        Unmanaged<OnDevicePairingManager>.fromOpaque(context).release()
        
        DispatchQueue.main.async {
            if rc != 0 || result.error != nil {
                let msg = result.error != nil ? String(cString: result.error!) : "Mã lỗi C: \(rc)"
                self.statusLog.append("❌ Pairing thất bại: \(msg)")
            } else {
                self.statusLog.append("✅ Pairing thành công! Đã lưu pairingFile.plist.")
                self.isSuccess = true
                UserDefaults.standard.set("pairingFile.plist", forKey: "PairingFile")
            }
            al_pairing_result_free(&result)
            self.stopPairing()
        }
    }
    
    private func advertiseBonjour(serviceId: String, port: UInt16, txtData: Data) {
        statusLog.append("Đang quảng bá Bonjour: \(serviceId) (Port \(port))")
        netService = NetService(domain: "local.", type: "_remotepairing-pairable-host._tcp.", name: serviceId, port: Int32(port))
        netService?.delegate = self
        netService?.setTXTRecord(txtData)
        netService?.publish(options: .listenForConnections)
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