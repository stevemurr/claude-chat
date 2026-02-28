import Foundation

enum SettingsKeys {
    static let useAPIService = "use_api_service"
    static let apiEndpoint = "api_endpoint"
    static let apiKey = "api_key"  // Legacy - now in Keychain
    static let selectedModel = "selected_model"
    static let syncServerURL = "syncServerURL"
    static let lastSyncTime = "lastSyncTime"
    static let claudePath = "claude_path"
    static let hotkeyConfig = "hotkey_config"
}
