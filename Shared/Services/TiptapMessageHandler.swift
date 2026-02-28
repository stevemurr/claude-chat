import Foundation
import WebKit
import os

/// Protocol for platform-specific actions triggered by Tiptap editor messages
@MainActor
protocol TiptapPlatformActions: AnyObject {
    func openURL(_ url: URL)
    func openFilePath(_ path: String)
}

/// Default no-op implementations for optional actions
extension TiptapPlatformActions {
    func openFilePath(_ path: String) {}
}

/// Shared message handler for Tiptap editor WebView messages.
/// Both macOS and iOS Coordinators delegate to this handler.
@MainActor
class TiptapMessageHandler {
    private static let logger = Logger(subsystem: "com.claude.ClaudeChat", category: "TiptapMessageHandler")

    let viewModel: TiptapEditorViewModel
    weak var platformActions: (any TiptapPlatformActions)?

    init(viewModel: TiptapEditorViewModel, platformActions: (any TiptapPlatformActions)?) {
        self.viewModel = viewModel
        self.platformActions = platformActions
    }

    /// All message handler names that should be registered with WKUserContentController
    static let messageHandlerNames = [
        "contentChanged",
        "editorReady",
        "openLink",
        "openFilePath",
        "openGroup",
        "navigateBack",
        "requestMentionItems",
        "openMention"
    ]

    /// Route a WKScriptMessage to the appropriate handler
    func handleMessage(_ message: WKScriptMessage) {
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
                platformActions?.openURL(url)
            }

        case "openFilePath":
            if let filePath = message.body as? String {
                platformActions?.openFilePath(filePath)
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
            Self.logger.warning("Unknown message from Tiptap editor: \(message.name)")
        }
    }
}
