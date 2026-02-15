import SwiftUI
import WebKit

// MARK: - TiptapEditorView (iOS UIViewRepresentable)

struct TiptapEditorView: UIViewRepresentable {
    @ObservedObject var viewModel: TiptapEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        userContentController.add(context.coordinator, name: "contentChanged")
        userContentController.add(context.coordinator, name: "editorReady")
        userContentController.add(context.coordinator, name: "openLink")

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
        let viewModel: TiptapEditorViewModel

        init(viewModel: TiptapEditorViewModel) {
            self.viewModel = viewModel
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                switch message.name {
                case "editorReady":
                    viewModel.handleEditorReady()

                case "contentChanged":
                    if let markdown = message.body as? String {
                        viewModel.handleContentChanged(markdown)
                    }

                case "openLink":
                    if let urlString = message.body as? String,
                       let url = URL(string: urlString) {
                        UIApplication.shared.open(url)
                    }

                default:
                    break
                }
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

            // Handle link clicks - open in Safari
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
