import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Endpoint")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("http://macbook-pro-8.tail11899.ts.net:8080", text: $settings.apiEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .onChange(of: settings.apiEndpoint) { _ in
                                availableModels = []
                                modelFetchError = nil
                            }
                    }
                } header: {
                    Text("Claude API")
                } footer: {
                    Text("Enter the URL of your OpenAI-compatible API server")
                }

                Section {
                    SecureField("Optional", text: $settings.apiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: settings.apiKey) { _ in
                            availableModels = []
                            modelFetchError = nil
                        }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Bearer token for authenticated endpoints")
                }

                Section {
                    HStack {
                        Button(action: { fetchModels() }) {
                            HStack {
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Fetch Models")
                            }
                        }
                        .disabled(isFetchingModels)
                    }

                    if !availableModels.isEmpty {
                        Picker("Model", selection: $settings.selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        HStack {
                            Text("Model")
                            Spacer()
                            TextField("claude-cli", text: $settings.selectedModel)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if let error = modelFetchError {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Select a model or enter one manually")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sync Server")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("http://macbook-pro-8.tail11899.ts.net:8081", text: $settings.syncServerURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Server for syncing notes across devices")
                }

                Section {
                    Link(destination: URL(string: "https://github.com/stevemurr/claude-cli-as-openai-api")!) {
                        HStack {
                            Text("API Server Setup Guide")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Help")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func fetchModels() {
        isFetchingModels = true
        modelFetchError = nil

        let urlString = settings.apiEndpoint.hasSuffix("/")
            ? "\(settings.apiEndpoint)v1/models"
            : "\(settings.apiEndpoint)/v1/models"

        guard let url = URL(string: urlString) else {
            modelFetchError = "Invalid endpoint URL"
            isFetchingModels = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        modelFetchError = "Invalid response"
                        isFetchingModels = false
                    }
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        if httpResponse.statusCode == 401 {
                            modelFetchError = "Authentication required — check your API key"
                        } else {
                            modelFetchError = "Server returned HTTP \(httpResponse.statusCode)"
                        }
                        isFetchingModels = false
                    }
                    return
                }

                let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
                let models = modelsResponse.data.map(\.id).sorted()

                await MainActor.run {
                    availableModels = models
                    if !models.contains(settings.selectedModel) {
                        settings.selectedModel = models.first ?? ""
                    }
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    modelFetchError = "Failed to fetch models: \(error.localizedDescription)"
                    isFetchingModels = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
