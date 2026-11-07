//  OnDevicePairingView.swift
//  EnsWilde

import SwiftUI

struct OnDevicePairingView: View {
    @StateObject private var manager = OnDevicePairingManager()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            Section {
                if manager.isPairing {
                    VStack(spacing: 12) {
                        Text("Nhập mã PIN này vào Cài đặt")
                            .font(.headline)
                        
                        Text(manager.pin.isEmpty ? "------" : manager.pin)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                        
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
                    .disabled(manager.isPairing)
                }
            } header: {
                Text("Pair On Device (iOS 27+)")
            } footer: {
                Text("Quảng bá Bonjour service để thiết bị tự pair với chính nó. Không cần máy tính.")
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
    }
}