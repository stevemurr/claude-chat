import Foundation

/// Shared environment setup for Process-based CLI invocations.
enum ProcessEnvironment {
    /// Returns a copy of the current environment with ~/.local/bin, /usr/local/bin,
    /// and /opt/homebrew/bin prepended to PATH.
    static func environmentWithCLIPaths() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let localBin = "\(homeDir)/.local/bin"
        let prefix = "\(localBin):/usr/local/bin:/opt/homebrew/bin"
        if let path = env["PATH"] {
            env["PATH"] = "\(prefix):" + path
        } else {
            env["PATH"] = "\(prefix):/usr/bin:/bin"
        }
        return env
    }
}
