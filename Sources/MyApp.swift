import SwiftUI
import UIKit
import UserNotifications

extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

@main
struct MyApp: App {
    private static let antiTamperMessage: String = "Fuck you. Get out..."

    init() {
        if Self.antiTamperMessage.isEmpty { return }

        let hexString = UserDefaults.standard.string(forKey: "EnsWilde.userTintColor") ?? "#ef9f76"
        let tintColor = UIColor(Color(hex: hexString))
        UIView.appearance(whenContainedInInstancesOf: [UIWindow.self]).tintColor = tintColor
        UITabBar.appearance().tintColor = tintColor
        UINavigationBar.appearance().tintColor = tintColor

        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            MainViewWithNavigation()
        }
    }
}

struct UnsupportedVersionView: View {
    var body: some View { EmptyView() }
}