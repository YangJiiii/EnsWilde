import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @ObservedObject var themeStore: PasscodeThemeStore
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolRunner: ToolRunner
    @ObservedObject var walletStore: AppleWalletStore
    @ObservedObject var featureFlagsStore: FeatureFlagsStore

    var showApplySheetBinding: Binding<Bool>? = nil
    var showStatusSheetBinding: Binding<Bool>? = nil
    var hideBottomApplyButton: Bool = false
    var isInNestedViewBinding: Binding<Bool>?
    var isSystemReadyBinding: Binding<Bool>?
    var heartbeatRunningBinding: Binding<Bool>?
    var ddiMountedBinding: Binding<Bool>?

    @State private var path = NavigationPath()
    @State private var _showApplySheet = false

    private var showApplySheet: Binding<Bool> {
        showApplySheetBinding ?? $_showApplySheet
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                statusSection
                tweaksSection
            }
            .headerProminence(.increased)
            .navigationTitle("EnsWilde")
            .navigationDestination(for: String.self) { route in
                destinationView(for: route)
            }
        }
        .onAppear {
            isSystemReadyBinding?.wrappedValue = true
            heartbeatRunningBinding?.wrappedValue = false
            ddiMountedBinding?.wrappedValue = false
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section(header: Text(L("section_status"))) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("bad_query active")
                        .font(.subheadline.bold())
                    Text("iOS 26.0 – 27.0b4 sandbox escape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var tweaksSection: some View {
        Section(header: Text(L("section_tweaks"))) {
            toolNavigationLink(
                value: "MobileGestalt",
                title: L("tool_mobile_gestalt"),
                subtitle: L("tool_mobile_gestalt_desc"),
                icon: "cpu",
                isEnabled: toolStore.replaceMobileGestaltEnabled
            )

            toolNavigationLink(
                value: "PasscodeTheme",
                title: L("tool_passcode_theme"),
                subtitle: L("tool_passcode_theme_desc"),
                icon: "lock.rectangle",
                isEnabled: themeStore.passcodeThemeEnabled
            )
        }
    }

    @ViewBuilder
    private func destinationView(for route: String) -> some View {
        if route == "MobileGestalt" {
            MobileGestaltView(toolStore: toolStore)
        } else if route == "PasscodeTheme" {
            PasscodeThemeView(themeStore: themeStore)
        }
    }

    @ViewBuilder
    private func toolNavigationLink(value: String, title: String, subtitle: String, icon: String, isEnabled: Bool) -> some View {
        NavigationLink(value: value) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } icon: {
                    Image(systemName: icon)
                }
                Spacer()
                if isEnabled {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
    }
}