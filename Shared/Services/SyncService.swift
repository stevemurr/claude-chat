import Foundation
import os

/// ISO 8601 date formatters with fractional-second support for sync encoding/decoding.
private enum SyncDateFormatters {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// Service for syncing notes with a remote server
@MainActor
class SyncService: ObservableObject {
    private static let logger = Logger(subsystem: "com.claude.ClaudeChat", category: "SyncService")

    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?

    private var syncEndpoint: URL? {
        guard let urlString = UserDefaults.standard.string(forKey: SettingsKeys.syncServerURL),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncDateFormatters.fractional.string(from: date))
        }
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = SyncDateFormatters.fractional.date(from: str) {
                return date
            }
            if let date = SyncDateFormatters.plain.date(from: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
        }
        return decoder
    }()

    // MARK: - Sync Operations

    /// Perform a full two-way sync with the server
    func sync(localNotes: [String: DailyNote]) async -> [String: DailyNote]? {
        guard let baseURL = syncEndpoint else {
            syncError = "Sync server not configured"
            return nil
        }

        Self.logger.info("Starting sync with \(baseURL), \(localNotes.count) local notes")

        isSyncing = true
        syncError = nil

        defer { isSyncing = false }

        let syncURL = baseURL.appendingPathComponent("sync")

        // Build sync request
        let request = SyncRequest(
            notes: Array(localNotes.values),
            lastSyncTime: lastSyncTime
        )

        do {
            var urlRequest = URLRequest(url: syncURL)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try encoder.encode(request)
            urlRequest.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                syncError = "Invalid response"
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                syncError = "Server error: \(httpResponse.statusCode)"
                return nil
            }

            let syncResponse = try decoder.decode(SyncResponse.self, from: data)

            // Update last sync time (try fractional seconds first)
            if let serverTime = SyncDateFormatters.fractional.date(from: syncResponse.serverTime)
                ?? SyncDateFormatters.plain.date(from: syncResponse.serverTime) {
                lastSyncTime = serverTime
                UserDefaults.standard.set(serverTime.timeIntervalSince1970, forKey: SettingsKeys.lastSyncTime)
            }

            // Merge server notes with local notes
            var mergedNotes = localNotes
            for serverNote in syncResponse.notes {
                if let existingNote = mergedNotes[serverNote.dateKey] {
                    // Keep the newer one
                    if serverNote.updatedAt > existingNote.updatedAt {
                        mergedNotes[serverNote.dateKey] = serverNote
                    }
                } else {
                    mergedNotes[serverNote.dateKey] = serverNote
                }
            }

            return mergedNotes

        } catch {
            syncError = error.localizedDescription
            Self.logger.error("Sync error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Push a single note to the server
    func pushNote(_ note: DailyNote) async -> Bool {
        guard let baseURL = syncEndpoint else {
            return false
        }

        let noteURL = baseURL.appendingPathComponent("notes").appendingPathComponent(note.dateKey)

        do {
            var urlRequest = URLRequest(url: noteURL)
            urlRequest.httpMethod = "PUT"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try encoder.encode(note)
            urlRequest.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            return true

        } catch {
            Self.logger.error("Push note error: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetch all notes from the server
    func fetchAllNotes() async -> [DailyNote]? {
        guard let baseURL = syncEndpoint else {
            return nil
        }

        let notesURL = baseURL.appendingPathComponent("notes")

        do {
            var urlRequest = URLRequest(url: notesURL)
            urlRequest.httpMethod = "GET"
            urlRequest.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            return try decoder.decode([DailyNote].self, from: data)

        } catch {
            Self.logger.error("Fetch notes error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Configuration

    func loadLastSyncTime() {
        let timestamp = UserDefaults.standard.double(forKey: SettingsKeys.lastSyncTime)
        if timestamp > 0 {
            lastSyncTime = Date(timeIntervalSince1970: timestamp)
        }
    }
}

// MARK: - Sync Models

struct SyncRequest: Codable {
    let notes: [DailyNote]
    let lastSyncTime: Date?
}

struct SyncResponse: Codable {
    let notes: [DailyNote]
    let serverTime: String
}
