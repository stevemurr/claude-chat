import Foundation

/// iOS Settings Manager - API configuration only (no hotkeys or CLI path)
/// Always uses API service (no CLI option on iOS)
class SettingsManager: SharedSettingsManager {
    static let shared = SettingsManager()

    override init() {
        super.init()
        // iOS always uses API service
        self.useAPIService = true
    }
}
