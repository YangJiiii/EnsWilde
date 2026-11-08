import Foundation
import SwiftUI

final class ToolStore: ObservableObject {
    @AppStorage("DisableDisclosureSoundEnabled") var disableSoundEnabled: Bool = false
    @AppStorage("SoundRespringEnabled") var soundRespringEnabled: Bool = true
    @AppStorage("BookassetdContainerUUID") var bookassetdUUID: String?

    @AppStorage("ReplaceMobileGestaltEnabled") var replaceMobileGestaltEnabled: Bool = false
    @AppStorage("ThemesUIEnabled") var themesUIEnabled: Bool = false
    @AppStorage("zPatchCustomEnabled") var zPatchCustomEnabled: Bool = false
    @AppStorage("zPatchUnlocked") var zPatchUnlocked: Bool = false
    @AppStorage("SoundDelayAfterStartSeconds") var soundDelayAfterStart: Double = 3.0
    @AppStorage("SoundDelayAfterStopSeconds") var soundDelayAfterStop: Double = 3.0
    @AppStorage("DeviceUDID") var deviceUDID: String = ""
    @AppStorage("ToolAEnabled") var toolAEnabled: Bool = false
    @AppStorage("ToolBEnabled") var toolBEnabled: Bool = false

    @AppStorage("ConfigTweaksEnabled") var configTweaksEnabled: Bool = false
    @AppStorage("ConfigFootnoteText") var configFootnoteText: String = ""

    // Trạng thái cho tính năng Disable Call Recording Sound
    @AppStorage("DisableCallRecordingSoundEnabled") var disableCallRecordingSoundEnabled: Bool = false

    // MARK: - Airlift mode helpers

    /// `true` = user đã bấm "Continue with Airlift" → app chạy Airlift-only.
    /// Config Tweaks & MobileGestalt BẮT BUỘC ẩn (chỉ Airlift dùng được).
    var isAirLiftOnlyMode: Bool {
        UserDefaults.standard.bool(forKey: "isAirLiftMode")
    }

    /// `true` = iOS hiện tại được support (không phải Airlift mode) → Config/MG chạy được.
    var isConfigAndMGAllowed: Bool {
        !isAirLiftOnlyMode
    }

    init() {
        // 🎯 Khi vào Airlift mode, force tắt Config + MobileGestalt.
        // Tránh trường hợp user đã bật từ trước rồi mới chọn Airlift.
        if UserDefaults.standard.bool(forKey: "isAirLiftMode") {
            UserDefaults.standard.set(false, forKey: "ConfigTweaksEnabled")
            UserDefaults.standard.set(false, forKey: "ReplaceMobileGestaltEnabled")
        }
    }
}