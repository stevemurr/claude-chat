import SwiftUI
import WebKit

// MARK: - macOS Platform Actions

class MacOSTiptapPlatformActions: TiptapPlatformActions {
    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openFilePath(_ path: String) {
        var expandedPath = path
        if expandedPath.hasPrefix("~") {
            expandedPath = NSString(string: expandedPath).expandingTildeInPath
        }
        let fileURL = URL(fileURLWithPath: expandedPath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            let parentURL = fileURL.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([parentURL])
            }
        }
    }
}

// MARK: - TiptapEditorView (macOS NSViewRepresentable)

struct TiptapEditorView: NSViewRepresentable {
    @ObservedObject var viewModel: TiptapEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        for name in TiptapMessageHandler.messageHandlerNames {
            userContentController.add(context.coordinator, name: name)
        }

        config.userContentController = userContentController
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.wantsLayer = true
        webView.layer?.drawsAsynchronously = true
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")

        // Enable Web Inspector for debugging
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        if let htmlURL = Bundle.main.url(forResource: "tiptap-editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        webView.navigationDelegate = context.coordinator
        viewModel.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if viewModel.noteDidChange() {
            viewModel.reloadFromNote()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let messageHandler: TiptapMessageHandler
        let platformActions: MacOSTiptapPlatformActions

        init(viewModel: TiptapEditorViewModel) {
            self.platformActions = MacOSTiptapPlatformActions()
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

            // Block all link navigation - we handle links via JavaScript message handlers
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
