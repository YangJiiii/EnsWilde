import Foundation
import UIKit

@MainActor
public class Alertinator {
    public static let shared = Alertinator()

    var alertController: UIAlertController?

    public func alert(title: String, body: String, showCancel: Bool = true) {
        Task { @MainActor in
            alertController = UIAlertController(title: title, message: body, preferredStyle: .alert)
            if showCancel {
                alertController?.addAction(.init(title: "OK", style: .cancel))
            }
            self.present(alertController!)
        }
    }

    public func alert(title: String, body: String, showCancel: Bool = true, actionLabel: String = "OK", action: @escaping () -> Void) {
        Task { @MainActor in
            alertController = UIAlertController(title: title, message: body, preferredStyle: .alert)
            alertController?.addAction(.init(title: actionLabel, style: .default) { _ in
                action()
            })
            if showCancel {
                alertController?.addAction(.init(title: "Cancel", style: .cancel))
            }
            self.present(alertController!)
        }
    }

    @MainActor
    private func present(_ alert: UIAlertController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           var topController = window.rootViewController {

            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }

            topController.present(alert, animated: true)
        }
    }
}