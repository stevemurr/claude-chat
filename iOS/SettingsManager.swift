import Foundation

/// iOS Settings Manager - API configuration only (no hotkeys or CLI path)
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var apiEndpoint: String {
        didSet {
            UserDefaults.standard.set(apiEndpoint, forKey: apiEndpointKey)
        }
    }

    @Published var syncServerURL: String {
        didSet {
            UserDefaults.standard.set(syncServerURL, forKey: syncServerURLKey)
        }
    }

    /// Always true on iOS - we can only use API, not CLI
    var useAPIService: Bool { true }

    private let apiEndpointKey = "api_endpoint"
    private let syncServerURLKey = "syncServerURL"

    private let currentTailnetHost = "macbook-pro-8.tail11899.ts.net"

    init() {
        // Load or set defaults
        if let savedEndpoint = UserDefaults.standard.string(forKey: apiEndpointKey), !savedEndpoint.isEmpty {
            self.apiEndpoint = savedEndpoint
        } else {
            self.apiEndpoint = "http://\(currentTailnetHost):8080"
        }

        if let savedSyncURL = UserDefaults.standard.string(forKey: syncServerURLKey), !savedSyncURL.isEmpty {
            self.syncServerURL = savedSyncURL
        } else {
            self.syncServerURL = "http://\(currentTailnetHost):8081"
        }

        // Migrate old URLs to tailnet
        migrateOldURLs()

        // didSet doesn't fire during init, so always ensure defaults are saved
        // This handles fresh installs where no migration occurs
        UserDefaults.standard.set(apiEndpoint, forKey: apiEndpointKey)
        UserDefaults.standard.set(syncServerURL, forKey: syncServerURLKey)
    }

    private func migrateOldURLs() {
        let oldPatterns = ["192.168.1.231", "localhost", "127.0.0.1"]
        var didMigrate = false

        for pattern in oldPatterns {
            if apiEndpoint.contains(pattern) {
                apiEndpoint = apiEndpoint.replacingOccurrences(of: pattern, with: currentTailnetHost)
                didMigrate = true
            }
            if syncServerURL.contains(pattern) {
                syncServerURL = syncServerURL.replacingOccurrences(of: pattern, with: currentTailnetHost)
                didMigrate = true
            }
        }

        // didSet doesn't fire during init, so save manually
        if didMigrate {
            UserDefaults.standard.set(apiEndpoint, forKey: apiEndpointKey)
            UserDefaults.standard.set(syncServerURL, forKey: syncServerURLKey)
            print("[SettingsManager] Migrated URLs to tailnet: \(currentTailnetHost)")
        }
    }
}
