import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
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
                    }
                } header: {
                    Text("Claude API")
                } footer: {
                    Text("Enter the URL of your OpenAI-compatible Claude API server")
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
}

#Preview {
    SettingsView()
}
