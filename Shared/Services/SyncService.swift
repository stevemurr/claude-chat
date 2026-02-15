import Foundation

/// Service for syncing notes with a remote server
@MainActor
class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?

    private var syncEndpoint: URL? {
        guard let urlString = UserDefaults.standard.string(forKey: "syncServerURL"),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Sync Operations

    /// Perform a full two-way sync with the server
    func sync(localNotes: [String: DailyNote]) async -> [String: DailyNote]? {
        guard let baseURL = syncEndpoint else {
            print("[SyncService] No sync endpoint configured. URL from defaults: \(UserDefaults.standard.string(forKey: "syncServerURL") ?? "nil")")
            syncError = "Sync server not configured"
            return nil
        }

        print("[SyncService] Starting sync with \(baseURL), \(localNotes.count) local notes")

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

            // Update last sync time
            if let serverTime = ISO8601DateFormatter().date(from: syncResponse.serverTime) {
                lastSyncTime = serverTime
                UserDefaults.standard.set(serverTime.timeIntervalSince1970, forKey: "lastSyncTime")
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
            print("[SyncService] Sync error: \(error)")
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
            print("Push note error: \(error)")
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
            print("Fetch notes error: \(error)")
            return nil
        }
    }

    // MARK: - Configuration

    func loadLastSyncTime() {
        let timestamp = UserDefaults.standard.double(forKey: "lastSyncTime")
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
