//
//  RespringHelper.swift
//  EnsWilde
//
//  NeoSpring implementation (credit: @neonmodder123 & @skadz108)
//

import UIKit
import Foundation
import WebKit

enum RespringError: Error, LocalizedError {
    case noWindow
    case failed

    var errorDescription: String? {
        switch self {
        case .noWindow:
            return "Không tìm thấy window để trigger respring"
        case .failed:
            return "Respring failed"
        }
    }
}

public final class RespringHelper: NSObject {

    public static let neospringHTML = """
<!DOCTYPE html>
<html>
    <body>
        <!-- big credit to @neonmodder123 & @skadz108 (neospring) -->
        <iframe id="frame" srcdoc="" sandbox="allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts"></iframe>
        <script>
            const frame = document.getElementById('frame');
            const funfun = `
                <html>
                <body>
                    <script>
                        const container = document.createElement('div');
                        container.style.cssText = 'perspective: 1px; perspective-origin: 9999999% 9999999%;';
                        document.body.appendChild(container);

                        for (let i = 0; i < 500; i++) {
                            let d = document.createElement('div');
                            d.style.cssText = 'position: absolute; width: 100vw; height: 100vh; backdrop-filter: blur(100px); -webkit-backdrop-filter: blur(100px); transform: translate3d(100000px, 100000px, ' + i + 'px) rotateY(90deg);';
                            container.appendChild(d);
                        }

                        setInterval(() => {
                            navigator.share({ title: 'R', text: 'R'.repeat(100000) }).catch(() => {});
                            let x = new Uint8Array(1024 * 1024 * 10);
                            crypto.getRandomValues(x);
                        }, 0);
                    <\\/script>
                </body>
                </html>
            `;

            frame.srcdoc = funfun;
        </script>
    </body>
</html>
"""

    public static func triggerNeoSpring() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow })
                    ?? windowScene.windows.first else {
                print("[NeoSpring] No window found")
                return
            }

            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = true

            let webView = WKWebView(frame: window.bounds, configuration: config)
            webView.isOpaque = true
            webView.backgroundColor = .black

            window.addSubview(webView)
            webView.loadHTMLString(neospringHTML, baseURL: nil)

            print("[NeoSpring] WebView attached, loading crash HTML...")
        }
    }

    public static func respring() throws {
        triggerNeoSpring()
    }
}