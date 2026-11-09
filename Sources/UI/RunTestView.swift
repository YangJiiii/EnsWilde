//
//  RunTestView.swift
//  EnsWilde
//

import SwiftUI

struct RunTestSectionView: View {
    @State private var isTesting = false
    @State private var resultMessage: String = ""
    @State private var isError: Bool = false
    
    var body: some View {
        Section(header: Text("Run Test (Kiểm tra quyền)")) {
            Button(action: testMobileGestaltWrite) {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text("Test ghi file MobileGestalt")
                    Spacer()
                    if isTesting {
                        ProgressView()
                    }
                }
            }
            .disabled(isTesting)
            
            if !resultMessage.isEmpty {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .green)
                    .padding(.vertical, 4)
            }
        }
    }
    
    private func testMobileGestaltWrite() {
        isTesting = true
        resultMessage = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Đường dẫn chuẩn của thư mục chứa MobileGestalt cache
            let targetDir = "/var/mobile/Containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
            let testFile = "\(targetDir)/enswilde_test_write.txt"
            let testContent = "EnsWilde App Group Test - \(Date())"
            
            // 1. Dùng WorseQuery xin quyền truy cập vào thư mục
            let bq = WorseQuery()
            let (granted, _) = bq.grantAccess(atPath: targetDir)
            
            if !granted {
                DispatchQueue.main.async {
                    self.isError = true
                    self.resultMessage = "❌ LỖI: WorseQuery không thể grant access. App Group chưa được ký đúng hoặc chứng chỉ không có quyền."
                    self.isTesting = false
                }
                return
            }
            
            // 2. Thử ghi file
            do {
                try testContent.write(toFile: testFile, atomically: true, encoding: .utf8)
                
                // Nếu ghi thành công thì xóa file test đi cho sạch
                try? FileManager.default.removeItem(atPath: testFile)
                
                DispatchQueue.main.async {
                    self.isError = false
                    self.resultMessage = "✅ THÀNH CÔNG! App Group đã hoạt động tốt. Có thể ghi file vào thư mục MobileGestalt."
                    self.isTesting = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isError = true
                    self.resultMessage = "❌ THẤT BẠI: Đã grant access nhưng ghi file lỗi:\n\(error.localizedDescription)"
                    self.isTesting = false
                }
            }
        }
    }
}