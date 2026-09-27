import Foundation
import SwiftUI

@MainActor
final class ToolRunner: ObservableObject {

    @Published var state: ToolRunState = .idle
    @Published var logs: [ToolRunLogLine] = []

    func resetLogs() {
        logs.removeAll()
    }

    func log(_ s: String) {
        logs.append(.init(text: s))
        print("[APPLY] \(s)")
    }

    func applyAll(store: ToolStore, themeStore: PasscodeThemeStore) async {
        resetLogs()

        let hasMobileGestalt = store.replaceMobileGestaltEnabled
        let hasPasscodeTheme = themeStore.passcodeThemeEnabled

        if !hasMobileGestalt && !hasPasscodeTheme {
            state = .failed(message: "No tweaks enabled.")
            log("Nothing to apply.")
            return
        }

        var names: [String] = []
        if hasMobileGestalt { names.append("MobileGestalt") }
        if hasPasscodeTheme { names.append("Passcode Theme") }
        log("Apply started. Enabled: \(names.joined(separator: ", "))")

        do {
            if hasMobileGestalt {
                state = .running(toolName: "MobileGestalt")
                log("Reading ModifiedMobileGestalt.plist...")

                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let modMGURL = docs.appendingPathComponent("ModifiedMobileGestalt.plist")

                guard FileManager.default.fileExists(atPath: modMGURL.path) else {
                    throw NSError(
                        domain: "ToolRunner", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing ModifiedMobileGestalt.plist. Save it first in MobileGestalt tool."]
                    )
                }

                let mgData = try Data(contentsOf: modMGURL)
                let targetPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"

                log("Writing via bad_query...")
                try BadQueryWrapper.writeFile(at: targetPath, data: mgData)
                log("✓ MobileGestalt written.")
            }

            if hasPasscodeTheme {
                state = .failed(message: "Passcode Theme chưa có exploit. Chờ cập nhật.")
                log("⚠ Passcode Theme skipped — no exploit available.")
                return
            }

            state = .success
            log("✓ Apply completed.")
        } catch {
            state = .failed(message: "\(error)")
            log("✗ Failed: \(error.localizedDescription)")
        }
    }
}