import SwiftUI

struct OnDevicePairingView: View {
    @StateObject private var manager = OnDevicePairingManager()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            Section {
                if manager.isPairing {
                    VStack(spacing: 16) {
                        Text("Nhập mã PIN này vào Cài đặt")
                            .font(.headline)
                        
                        HStack {
                            Text(manager.pin.isEmpty ? "------" : manager.pin)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)
                            
                            if !manager.pin.isEmpty {
                                Button {
                                    UIPasteboard.general.string = manager.pin
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.title2)
                                }
                            }
                        }
                        
                        Text("Cài đặt > Quyền riêng tư & Bảo mật > Chế độ nhà phát triển > Pair with EnsWilde")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if manager.isSuccess {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Pairing Thành Công!")
                            .font(.headline)
                        Button("Đóng") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Button("Bắt đầu Pair On Device") {
                        manager.startPairing()
                    }
                }
            } header: {
                Text("Pair On Device (iOS 27+)")
            } footer: {
                Text("App đã được bật chế độ chạy ngầm vô hạn. Bạn có thể yên tâm chuyển sang Settings để nhập PIN mà không lo bị iOS tắt.")
            }
            
            if !manager.statusLog.isEmpty {
                Section("Log") {
                    ForEach(manager.statusLog, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            
            if manager.isPairing {
                Section {
                    Button("Hủy", role: .destructive) {
                        manager.stopPairing()
                    }
                }
            }
        }
        .navigationTitle("Pair On Device")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Dọn dẹp khi view bị đóng để tránh rò rỉ
            manager.stopPairing()
        }
    }
}