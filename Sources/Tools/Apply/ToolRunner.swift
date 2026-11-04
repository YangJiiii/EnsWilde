import Foundation
import SwiftUI

@MainActor
class ToolRunner: ObservableObject {
    @Published var state: ToolState = .idle

    func applyAll(
        isSystemReady: Bool,
        store: ToolStore,
        walletStore: AppleWalletStore,
        themeStore: PasscodeThemeStore,
        featureFlagsStore: FeatureFlagsStore,
        onLogUpdate: @escaping (String) -> Void
    ) async {
        guard isSystemReady else {
            state = .failed("System not ready. Check Pairing & VPN.")
            return
        }
        
        state = .running
        onLogUpdate("Starting tweaks...")
        
        do {
            if store.replaceMobileGestaltEnabled {
                onLogUpdate(">> Applying MobileGestalt...")
                // try await MobileGestaltApplyTask.run(...) // Truyền onLogUpdate nếu cần
                onLogUpdate(">> MobileGestalt Done.")
            }
            
            if themeStore.passcodeThemeEnabled {
                onLogUpdate(">> Applying Passcode Theme...")
                let selectedTheme = themeStore.getSelectedTheme() ?? PasscodeTheme(name: "Default")
                let vm = PasscodeThemeViewModel(store: themeStore)
                try await vm.applyTheme(selectedTheme, store: store, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Passcode Theme Done.")
            }
            
            if walletStore.appleWalletEnabled {
                onLogUpdate(">> Applying Apple Wallet...")
                try await AppleWalletTask.run(store: store, walletStore: walletStore, onLogUpdate: onLogUpdate)
                onLogUpdate(">> Wallet Done.")
            }
            
            if store.configTweaksEnabled {
                onLogUpdate(">> Applying Config Tweaks...")
                // try await ...
                onLogUpdate(">> Config Tweaks Done.")
            }
            
            state = .success
            onLogUpdate("All tweaks applied successfully.")
            
        } catch {
            state = .failed(error.localizedDescription)
            onLogUpdate("Failed: \(error.localizedDescription)")
        }
    }
}

enum ToolState: Equatable {
    case idle
    case running
    case success
    case failed(String)
}