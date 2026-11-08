import SwiftUI

struct TweaksView: View {
    @ObservedObject var toolStore: ToolStore
    @AppStorage("isAirLiftMode") private var isAirLiftMode: Bool = false // Thêm để nhận biết chế độ Airlift

    var body: some View {
        NavigationStack {
            List {
                // Chỉ hiển thị các tweaks yêu cầu quyền Native (MobileGestalt, Config Tweaks) khi KHÔNG ở Airlift mode
                if !isAirLiftMode {
                    Section {
                        NavigationLink {
                            MobileGestaltView(toolStore: toolStore)
                        } label: {
                            Label("MobileGestalt", systemImage: "cpu")
                        }
                        
                        NavigationLink {
                            ConfigView(toolStore: toolStore)
                        } label: {
                            Label("Config Tweaks", systemImage: "slider.horizontal.3")
                        }
                    } header: {
                        Label("System", systemImage: "gear")
                            .font(.subheadline.bold())
                    }
                } else {
                    // Thông báo thay thế khi ở Airlift mode
                    Section {
                        Text("Các tweaks yêu cầu quyền hệ thống (MobileGestalt, Config) không khả dụng trong Airlift mode. Vui lòng sử dụng Passcode Theme.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } header: {
                        Label("Airlift Mode", systemImage: "airplane")
                            .font(.subheadline.bold())
                    }
                }
            }
            .navigationTitle("Tweaks")
        }
    }
}