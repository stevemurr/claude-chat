import SwiftUI
import WebKit

// MARK: - TiptapEditorView (macOS NSViewRepresentable)

struct TiptapEditorView: NSViewRepresentable {
    @ObservedObject var viewModel: TiptapEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        userContentController.add(context.coordinator, name: "contentChanged")
        userContentController.add(context.coordinator, name: "editorReady")
        userContentController.add(context.coordinator, name: "openLink")
        userContentController.add(context.coordinator, name: "openFilePath")
        userContentController.add(context.coordinator, name: "openGroup")
        userContentController.add(context.coordinator, name: "navigateBack")
        userContentController.add(context.coordinator, name: "requestMentionItems")
        userContentController.add(context.coordinator, name: "openMention")

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
                        NSWorkspace.shared.open(url)
                    }

                case "openFilePath":
                    if let filePath = message.body as? String {
                        var expandedPath = filePath
                        // Handle ~ (home directory) paths
                        if expandedPath.hasPrefix("~") {
                            expandedPath = NSString(string: expandedPath).expandingTildeInPath
                        }
                        let fileURL = URL(fileURLWithPath: expandedPath)
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        } else {
                            // File doesn't exist, try to open parent directory
                            let parentURL = fileURL.deletingLastPathComponent()
                            if FileManager.default.fileExists(atPath: parentURL.path) {
                                NSWorkspace.shared.activateFileViewerSelecting([parentURL])
                            }
                        }
                    }

                case "openGroup":
                    if let groupData = message.body as? [String: Any],
                       let groupId = groupData["id"] as? String,
                       let groupTitle = groupData["title"] as? String {
                        viewModel.navigateIntoGroup(id: groupId, title: groupTitle)
                    }

                case "navigateBack":
                    if viewModel.groupNavigation.isInsideGroup {
                        viewModel.navigateBack()
                    }

                case "requestMentionItems":
                    let query = message.body as? String ?? ""
                    viewModel.handleMentionItemsRequest(query: query)

                case "openMention":
                    if let data = message.body as? [String: Any] {
                        viewModel.handleOpenMention(data: data)
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

            // Block all link navigation - we handle links via JavaScript message handlers
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
