//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct ProvidersPage: View {

    let controller: AppController
    let provider: Provider

    @State private var isModelMenuPresented = false
    @State private var apiKey = ""
    @State private var models: [ModelDescriptor] = []
    @State private var isRefreshingModels = false
    @State private var statusMessage: String?
    @State private var isStatusError = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    TextField(
                        "Base URL",
                        text: baseURLBinding,
                        prompt: Text(provider.defaultBaseURL)
                    )
                    .labelsHidden()
                    .accessibilityLabel("Base URL")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                } label: {
                    Text("Base URL")
                    Text("The API endpoint used for requests.")
                }

                if provider.requiresAPIKey {
                    LabeledContent {
                        SecureField("API Key", text: apiKeyBinding)
                            .labelsHidden()
                            .accessibilityLabel("API Key")
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    } label: {
                        Text("API Key")
                        Text("Stored securely in Keychain.")
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                if provider.requiresAPIKey {
                    Text("Requests are sent directly to \(provider.name).")
                } else {
                    Text("Make sure Ollama is running before refreshing models.")
                }
            }

            Section("Model") {
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField(
                            "Model ID",
                            text: modelIDBinding,
                            prompt: Text("Enter model ID")
                        )
                        .labelsHidden()
                        .accessibilityLabel("Model ID")
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 216)

                        Button {
                            isModelMenuPresented.toggle()
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(models.isEmpty)
                        .help("Choose from available models")
                        .popoverPanel(isPresented: $isModelMenuPresented) {
                            SearchableMenu(
                                items: models.map { model in
                                    SearchableMenuItem(
                                        id: model.id,
                                        title: model.displayName,
                                        searchTerms: [model.id]
                                    )
                                },
                                selectedID: modelIDBinding.wrappedValue,
                                searchPrompt: "Search Models"
                            ) { modelID in
                                modelIDBinding.wrappedValue = modelID
                                isModelMenuPresented = false
                            } onCancel: {
                                isModelMenuPresented = false
                            }
                            .frame(width: 340, height: 280)
                        }
                    }
                } label: {
                    Text("Model ID")
                    Text("Enter an ID or choose a fetched model.")
                }

                LabeledContent {
                    refreshModelsButton
                } label: {
                    Text("Available Models")
                    Text(modelAvailabilityDescription)
                }

                Toggle(isOn: thinkingEnabledBinding) {
                    Text("Extended Thinking")
                    Text("Use reasoning mode when the selected model supports it.")
                }

                if let statusMessage {
                    Label(
                        statusMessage,
                        systemImage: isStatusError
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(isStatusError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            loadConfiguration()
        }
        .onChange(of: provider) {
            loadConfiguration()
        }
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { controller.settings.baseURL(for: provider.id) },
            set: { controller.settings.setBaseURL($0, for: provider.id) }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKey },
            set: { newValue in
                apiKey = newValue
                do {
                    try controller.credentials.setAPIKey(newValue, for: provider.id)
                    controller.session.refreshCredentialAvailability()
                    statusMessage = nil
                    isStatusError = false
                } catch {
                    statusMessage = error.localizedDescription
                    isStatusError = true
                }
            }
        )
    }

    private var modelIDBinding: Binding<String> {
        Binding(
            get: { controller.settings.modelID(for: provider.id) },
            set: { controller.settings.setModelID($0, for: provider.id) }
        )
    }

    private var thinkingEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.thinkingEnabled(for: provider.id) },
            set: { controller.settings.setThinkingEnabled($0, for: provider.id) }
        )
    }

    private var refreshModelsButton: some View {
        Button {
            refreshModels()
        } label: {
            HStack(spacing: 6) {
                if isRefreshingModels {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isRefreshingModels ? "Refreshing…" : "Refresh Models")
            }
        }
        .disabled(isRefreshingModels)
    }

    private var modelAvailabilityDescription: String {
        if models.isEmpty {
            "Fetch from \(provider.name), or enter an ID manually."
        } else {
            "\(models.count) models available."
        }
    }

    private func loadConfiguration() {
        models = controller.settings.cachedModels(for: provider.id)
        apiKey = (try? controller.credentials.apiKey(for: provider.id)) ?? ""
        statusMessage = nil
        isStatusError = false
    }

    private func refreshModels() {
        let baseURL = controller.settings.baseURL(for: provider.id)
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "Enter a valid provider base URL."
            isStatusError = true
            return
        }

        isRefreshingModels = true
        statusMessage = nil
        Task {
            do {
                let configuration = ProviderConfiguration(
                    providerID: provider.id,
                    baseURL: url,
                    modelID: controller.settings.modelID(for: provider.id),
                    apiKey: provider.requiresAPIKey ? apiKey : nil,
                    thinkingEnabled: controller.settings.thinkingEnabled(for: provider.id)
                )
                let adapter = ProviderAdapterRegistry.adapter(for: provider.id)
                models = try await adapter.fetchModels(configuration: configuration)
                controller.settings.setCachedModels(models, for: provider.id)
                statusMessage = models.isEmpty
                    ? "No models were returned. You can still enter a model ID manually."
                    : "Loaded \(models.count) models."
                isStatusError = false
            } catch {
                statusMessage = "\(error.localizedDescription) You can still enter a model ID manually."
                isStatusError = true
            }
            isRefreshingModels = false
        }
    }
}