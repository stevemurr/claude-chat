import Foundation
import Combine

@MainActor
class SharedSettingsManager: ObservableObject {
    @Published var useAPIService: Bool {
        didSet { UserDefaults.standard.set(useAPIService, forKey: SettingsKeys.useAPIService) }
    }

    @Published var apiEndpoint: String {
        didSet { UserDefaults.standard.set(apiEndpoint, forKey: SettingsKeys.apiEndpoint) }
    }

    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: SettingsKeys.selectedModel) }
    }

    @Published var syncServerURL: String {
        didSet { UserDefaults.standard.set(syncServerURL, forKey: SettingsKeys.syncServerURL) }
    }

    // API key backed by Keychain, with @Published for SwiftUI binding support
    @Published var apiKey: String {
        didSet { _ = KeychainHelper.save(key: SettingsKeys.apiKey, value: apiKey) }
    }

    init() {
        self.useAPIService = UserDefaults.standard.bool(forKey: SettingsKeys.useAPIService)
        self.apiEndpoint = UserDefaults.standard.string(forKey: SettingsKeys.apiEndpoint) ?? ""
        self.selectedModel = UserDefaults.standard.string(forKey: SettingsKeys.selectedModel) ?? ""
        self.syncServerURL = UserDefaults.standard.string(forKey: SettingsKeys.syncServerURL) ?? ""

        // Load API key from Keychain (or migrate from UserDefaults)
        if let oldKey = UserDefaults.standard.string(forKey: SettingsKeys.apiKey), !oldKey.isEmpty {
            // Migrate from UserDefaults to Keychain
            _ = KeychainHelper.save(key: SettingsKeys.apiKey, value: oldKey)
            UserDefaults.standard.removeObject(forKey: SettingsKeys.apiKey)
            self.apiKey = oldKey
        } else {
            self.apiKey = KeychainHelper.load(key: SettingsKeys.apiKey) ?? ""
        }
    }
}
