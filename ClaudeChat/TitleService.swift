import Foundation

@MainActor
class TitleService: ObservableObject {

    func generateTitle(for content: String) async -> String? {
        guard let claudePath = SettingsManager.shared.resolveClaudePath() else {
            return nil
        }

        let truncated = String(content.prefix(500))
        let prompt = "Generate a concise 3-6 word title for this content. Reply with ONLY the title, nothing else:\n\n\(truncated)"

        return await Task.detached(priority: .utility) {
            await self.runClaude(path: claudePath, prompt: prompt)
        }.value
    }

    private nonisolated func runClaude(path: String, prompt: String) async -> String? {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-p", prompt, "--output-format", "stream-json"]
        process.standardOutput = pipe
        process.standardError = errorPipe

        // Same PATH/env setup as ClaudeService
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let localBin = "\(homeDir)/.local/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(localBin):/usr/local/bin:/opt/homebrew/bin:" + existingPath
        } else {
            env["PATH"] = "\(localBin):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        process.environment = env

        do {
            try process.run()

            let fileHandle = pipe.fileHandleForReading
            let decoder = JSONDecoder()
            var resultText = ""

            while process.isRunning || fileHandle.availableData.count > 0 {
                let data = fileHandle.availableData
                if data.isEmpty {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }

                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        if let lineData = line.data(using: .utf8),
                           let msg = try? decoder.decode(StreamMessage.self, from: lineData) {
                            if msg.type == "assistant", let content = msg.message?.content {
                                for block in content {
                                    if block.type == "text", let text = block.text {
                                        resultText = text
                                    }
                                }
                            }
                            if msg.type == "result", let text = msg.result, !text.isEmpty {
                                resultText = text
                            }
                        }
                    }
                }
            }

            process.waitUntilExit()

            let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
