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

        let targetDir = "/var/mobile/Containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"
        let testFile = "\(targetDir)/enswilde_test_write.txt"
        let testContent = "EnsWilde App Group Test - \(Date())"

        Task {
            let result: (isError: Bool, message: String) = await Task.detached(priority: .userInitiated) {
                let bq = WorseQuery()
                let (granted, _) = bq.grantAccess(atPath: targetDir)

                if !granted {
                    return (true, "❌ LỖI: WorseQuery không thể grant access. App Group chưa được ký đúng hoặc chứng chỉ không có quyền.")
                }

                do {
                    try testContent.write(toFile: testFile, atomically: true, encoding: .utf8)
                    try? FileManager.default.removeItem(atPath: testFile)
                    return (false, "✅ THÀNH CÔNG! App Group đã hoạt động tốt. Có thể ghi file vào thư mục MobileGestalt.")
                } catch {
                    return (true, "❌ THẤT BẠI: Đã grant access nhưng ghi file lỗi:\n\(error.localizedDescription)")
                }
            }.value

            self.isError = result.isError
            self.resultMessage = result.message
            self.isTesting = false
        }
    }
}