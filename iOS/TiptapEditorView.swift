import SwiftUI
import WebKit

// MARK: - iOS Platform Actions

class iOSTiptapPlatformActions: TiptapPlatformActions {
    func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - TiptapEditorView (iOS UIViewRepresentable)

struct TiptapEditorView: UIViewRepresentable {
    @ObservedObject var viewModel: TiptapEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        for name in TiptapMessageHandler.messageHandlerNames {
            userContentController.add(context.coordinator, name: name)
        }

        config.userContentController = userContentController
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        if let htmlURL = Bundle.main.url(forResource: "tiptap-editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        webView.navigationDelegate = context.coordinator
        viewModel.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if viewModel.noteDidChange() {
            viewModel.reloadFromNote()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let messageHandler: TiptapMessageHandler
        let platformActions: iOSTiptapPlatformActions

        init(viewModel: TiptapEditorViewModel) {
            self.platformActions = iOSTiptapPlatformActions()
            self.messageHandler = TiptapMessageHandler(viewModel: viewModel, platformActions: platformActions)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                messageHandler.handleMessage(message)
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow initial file load
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link clicks - open in default browser
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
