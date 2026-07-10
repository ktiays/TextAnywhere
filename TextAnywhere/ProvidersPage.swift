//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct ProvidersPage: View {

    let controller: AppController

    @State private var selectedProvider = Provider.bailian
    @State private var isProviderMenuPresented = false
    @State private var isModelMenuPresented = false
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelID = ""
    @State private var isThinkingEnabled = false
    @State private var models: [ModelDescriptor] = []
    @State private var isRefreshingModels = false
    @State private var statusMessage: String?
    @State private var isStatusError = false

    var body: some View {
        Form {
            LabeledContent("AI Provider") {
                providerButton
            }

            LabeledContent("Base URL") {
                TextField("Provider Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
            }

            if selectedProvider.requiresAPIKey {
                LabeledContent("API Key") {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
            }

            LabeledContent("Model") {
                HStack(spacing: 8) {
                    TextField("Model ID", text: $modelID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)

                    Button {
                        isModelMenuPresented.toggle()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(models.isEmpty)
                    .popoverPanel(isPresented: $isModelMenuPresented) {
                        ModelMenuContent(models: models, selectedModelID: $modelID) {
                            isModelMenuPresented = false
                        }
                        .frame(width: 340, height: 280)
                    }
                }
            }

            LabeledContent("Thinking") {
                VStack(alignment: .trailing, spacing: 4) {
                    Toggle("", isOn: $isThinkingEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text("Requires a model that supports thinking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()

                Button("Save") {
                    saveConfiguration()
                }

                Button {
                    refreshModels()
                } label: {
                    if isRefreshingModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Refresh Models")
                    }
                }
                .disabled(isRefreshingModels)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(isStatusError ? Color.red : Color.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fontDesign(.rounded)
        .onAppear {
            selectedProvider = controller.settings.selectedProvider
            loadConfiguration()
        }
        .onChange(of: selectedProvider) {
            controller.settings.selectedProviderID = selectedProvider.id
            loadConfiguration()
        }
    }

    private var providerButton: some View {
        Button {
            isProviderMenuPresented.toggle()
        } label: {
            HStack {
                selectedProvider.iconView()
                    .frame(width: 16, height: 16)
                Text(selectedProvider.name)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180)
        }
        .buttonStyle(.bordered)
        .popoverPanel(isPresented: $isProviderMenuPresented) {
            ProviderMenuContent(selectedProvider: $selectedProvider) {
                isProviderMenuPresented = false
            }
            .frame(width: 320, height: 280)
        }
    }

    private func loadConfiguration() {
        baseURL = controller.settings.baseURL(for: selectedProvider.id)
        modelID = controller.settings.modelID(for: selectedProvider.id)
        isThinkingEnabled = controller.settings.thinkingEnabled(for: selectedProvider.id)
        models = controller.settings.cachedModels(for: selectedProvider.id)
        apiKey = (try? controller.credentials.apiKey(for: selectedProvider.id)) ?? ""
        statusMessage = nil
        isStatusError = false
    }

    private func saveConfiguration(showConfirmation: Bool = true) {
        do {
            controller.settings.setBaseURL(baseURL, for: selectedProvider.id)
            controller.settings.setModelID(modelID, for: selectedProvider.id)
            controller.settings.setThinkingEnabled(isThinkingEnabled, for: selectedProvider.id)
            if selectedProvider.requiresAPIKey {
                try controller.credentials.setAPIKey(apiKey, for: selectedProvider.id)
            }
            isStatusError = false
            if showConfirmation {
                statusMessage = "Configuration saved."
            } else {
                statusMessage = nil
            }
        } catch {
            statusMessage = error.localizedDescription
            isStatusError = true
        }
    }

    private func refreshModels() {
        saveConfiguration(showConfirmation: false)
        guard !isStatusError else { return }
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
                    providerID: selectedProvider.id,
                    baseURL: url,
                    modelID: modelID,
                    apiKey: selectedProvider.requiresAPIKey ? apiKey : nil,
                    thinkingEnabled: isThinkingEnabled
                )
                let adapter = ProviderAdapterRegistry.adapter(for: selectedProvider.id)
                models = try await adapter.fetchModels(configuration: configuration)
                controller.settings.setCachedModels(models, for: selectedProvider.id)
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

private struct ProviderMenuContent: View {

    @Binding var selectedProvider: Provider
    let onSelect: () -> Void

    @State private var searchText = ""
    @State private var highlightedProviderID: ProviderIdentifier?

    private var providers: [Provider] {
        guard !searchText.isEmpty else { return Provider.presets }
        return Provider.presets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Providers", text: $searchText)
                .textFieldStyle(.plain)
                .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(providers) { provider in
                        HStack {
                            provider.iconView()
                                .frame(width: 16, height: 16)
                            Text(provider.name)
                            Spacer()
                            if selectedProvider == provider {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            if highlightedProviderID == provider.id {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.tint.opacity(0.1))
                            }
                        }
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            highlightedProviderID = isHovered ? provider.id : nil
                        }
                        .onTapGesture {
                            selectedProvider = provider
                            onSelect()
                        }
                    }
                }
                .padding(8)
            }
        }
        .fontDesign(.rounded)
    }
}

private struct ModelMenuContent: View {

    let models: [ModelDescriptor]
    @Binding var selectedModelID: String
    let onSelect: () -> Void

    @State private var searchText = ""

    private var filteredModels: [ModelDescriptor] {
        guard !searchText.isEmpty else { return models }
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Models", text: $searchText)
                .textFieldStyle(.plain)
                .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredModels) { model in
                        HStack {
                            Text(model.displayName)
                                .lineLimit(1)
                            Spacer()
                            if selectedModelID == model.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedModelID = model.id
                            onSelect()
                        }
                    }
                }
                .padding(8)
            }
        }
        .fontDesign(.rounded)
    }
}
