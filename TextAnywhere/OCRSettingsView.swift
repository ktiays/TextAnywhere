//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct OCRSettingsView: View {

    let controller: AppController

    @State private var shortcutErrorMessage: String?
    @State private var isModelMenuPresented = false
    @State private var modelList = OCRModelList()
    @State private var modelRefreshTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { settings.isOCREnabled },
                        set: { isEnabled in
                            settings.isOCREnabled = isEnabled
                            applyOCRShortcut()
                        }
                    )
                ) {
                    Text("Enable OCR")
                    Text("Recognize text in images and add it to the editor draft.")
                }

                LabeledContent("Provider") {
                    if settings.enabledProviders.isEmpty {
                        Text("No Providers Enabled")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "Provider",
                            selection: Binding(
                                get: { settings.ocrProviderID },
                                set: { settings.ocrProviderID = $0 }
                            )
                        ) {
                            ForEach(settings.enabledProviders) { provider in
                                Text(provider.name)
                                    .tag(provider.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220, alignment: .trailing)
                    }
                }
                .disabled(!settings.isOCREnabled)

                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("Model ID", text: modelIDBinding, prompt: Text("Enter model ID"))
                            .labelsHidden()
                            .accessibilityLabel("OCR Model ID")
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 176)

                        Button(action: toggleModelMenu) {
                            Image(systemName: "chevron.down")
                        }
                        .accessibilityLabel("Choose OCR Model")
                        .help("Choose from available models")
                        .popoverPanel(isPresented: $isModelMenuPresented) {
                            OCRModelMenu(
                                settings: settings,
                                modelList: modelList,
                                isPresented: $isModelMenuPresented
                            )
                            .frame(width: 340, height: 420)
                        }
                    }
                } label: {
                    Text("Model")
                    Text("Choose a model that supports image input.")
                }
                .accessibilityElement(children: .contain)
                .disabled(!settings.isOCREnabled || settings.enabledProviders.isEmpty)

                if let modelErrorMessage = modelList.errorMessage {
                    Text(modelErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Mode") {
                    Picker(
                        "Mode",
                        selection: Binding(
                            get: { settings.ocrMode },
                            set: { settings.ocrMode = $0 }
                        )
                    ) {
                        ForEach(OCRMode.allCases) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }
                .disabled(!settings.isOCREnabled)

                Toggle(
                    isOn: Binding(
                        get: { settings.isOCRHTMLTableConversionEnabled },
                        set: { settings.isOCRHTMLTableConversionEnabled = $0 }
                    )
                ) {
                    Text("Convert HTML Tables")
                    Text("Rewrites recognized HTML tables as Markdown tables. Merged cells are split into empty cells.")
                }
                .disabled(!settings.isOCREnabled)
            } footer: {
                Text("Images are sent directly to the selected provider and model. Configure the connection in Providers. Recognize and Translate uses the editor’s language selection to recognize and translate in one request. PDF pages are sent as images.")
            }

            Section {
                Toggle(
                    isOn: Binding(
                        get: { settings.isOCRScreenCaptureEnabled },
                        set: { settings.isOCRScreenCaptureEnabled = $0 }
                    )
                ) {
                    Text("Screen Capture")
                    Text("Adds a button to the editor for selecting an area of the screen.")
                }

                Toggle(
                    isOn: Binding(
                        get: { settings.isOCRPasteAndDropEnabled },
                        set: { settings.isOCRPasteAndDropEnabled = $0 }
                    )
                ) {
                    Text("Paste and Drop")
                    Text("Recognizes images and PDFs pasted or dropped into the editor.")
                }

                Toggle(
                    isOn: Binding(
                        get: { settings.isOCRFilePickerEnabled },
                        set: { settings.isOCRFilePickerEnabled = $0 }
                    )
                ) {
                    Text("Choose File")
                    Text("Adds a button to the editor for opening an image or PDF.")
                }

                Toggle(
                    isOn: Binding(
                        get: { settings.isOCRShortcutEnabled },
                        set: { isEnabled in
                            settings.isOCRShortcutEnabled = isEnabled
                            applyOCRShortcut()
                        }
                    )
                ) {
                    Text("Global Shortcut")
                    Text("Select an area of the screen from any app and open the editor with its text.")
                }

                if settings.isOCRShortcutEnabled {
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        ShortcutRecorderView(shortcut: settings.ocrShortcut) { shortcut in
                            try controller.updateOCRShortcut(shortcut)
                        }
                    }
                }

                if let shortcutErrorMessage {
                    Text(shortcutErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Entry Points")
            }
            .disabled(!settings.isOCREnabled)

            Section {
                LabeledContent("Screen Recording") {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if ScreenCapture.hasPermission {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Grant Access") {
                                ScreenCapture.requestPermission()
                            }
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Screen capture and the global shortcut need Screen Recording access. Restart TextAnywhere after granting it.")
            }
        }
        .fontDesign(.rounded)
        .onAppear(perform: loadModelChoices)
        .onChange(of: settings.ocrProviderID) {
            loadModelChoices()
            controller.session.refreshCredentialAvailability()
        }
        .onDisappear {
            modelRefreshTask?.cancel()
            modelRefreshTask = nil
        }
    }

    private var settings: AppSettings {
        controller.settings
    }

    private var modelIDBinding: Binding<String> {
        Binding(
            get: { settings.ocrModelID },
            set: { settings.setOCRModelID($0, for: settings.ocrProviderID) }
        )
    }

    private func loadModelChoices() {
        modelRefreshTask?.cancel()
        modelRefreshTask = nil
        isModelMenuPresented = false
        modelList.isRefreshing = false
        modelList.errorMessage = nil
        modelList.models = settings.cachedModels(for: settings.ocrProviderID)
    }

    private func toggleModelMenu() {
        isModelMenuPresented.toggle()
        if isModelMenuPresented {
            refreshModels()
        }
    }

    private func refreshModels() {
        guard !modelList.isRefreshing else { return }
        let provider = settings.ocrProvider
        let baseURL = settings.baseURL(for: provider.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            modelList.errorMessage = "Enter a valid base URL in Providers → \(provider.name)."
            return
        }
        modelList.isRefreshing = true
        modelList.errorMessage = nil
        modelRefreshTask = Task {
            do {
                let configuration = ProviderConfiguration(
                    providerID: provider.id,
                    baseURL: url,
                    modelID: settings.ocrModelID,
                    apiKey: provider.requiresAPIKey ? try controller.credentials.apiKey(for: provider.id) : nil,
                    thinkingEnabled: settings.thinkingEnabled(for: provider.id)
                )
                let fetchedModels = try await ProviderAdapterRegistry.adapter(for: provider.id)
                    .fetchModels(configuration: configuration)
                guard !Task.isCancelled, settings.ocrProviderID == provider.id else { return }
                modelList.models = fetchedModels
                settings.setCachedModels(fetchedModels, for: provider.id)
                if fetchedModels.isEmpty {
                    modelList.errorMessage = "No models were returned. You can enter a model ID manually."
                }
            } catch {
                guard !Task.isCancelled, settings.ocrProviderID == provider.id else { return }
                modelList.errorMessage = "\(error.localizedDescription) You can enter a model ID manually."
            }
            modelList.isRefreshing = false
            modelRefreshTask = nil
        }
    }

    private func applyOCRShortcut() {
        do {
            try controller.applyOCRShortcut()
            shortcutErrorMessage = nil
        } catch {
            settings.isOCRShortcutEnabled = false
            shortcutErrorMessage = "The OCR shortcut couldn't be registered: \(error.localizedDescription)"
        }
    }
}

/// Shared between the settings form and the model popover, whose content is hosted separately
/// and only picks up changes through observation.
@MainActor
@Observable
private final class OCRModelList {

    var models: [ModelDescriptor] = []
    var isRefreshing = false
    var errorMessage: String?

    func choices(for settings: AppSettings) -> [ModelDescriptor] {
        var choices = models
        for modelID in [settings.ocrModelID, settings.modelID(for: settings.ocrProviderID)] {
            let identifier = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty, !choices.contains(where: { $0.id == identifier }) {
                choices.append(ModelDescriptor(id: identifier, displayName: identifier))
            }
        }
        return choices
    }
}

private struct OCRModelMenu: View {

    let settings: AppSettings
    let modelList: OCRModelList
    @Binding var isPresented: Bool

    var body: some View {
        SearchableMenu(
            items: modelList.choices(for: settings).map { model in
                SearchableMenuItem(
                    id: model.id,
                    title: model.displayName,
                    searchTerms: [model.id]
                )
            },
            selectedID: settings.ocrModelID,
            searchPrompt: "Search Models",
            isLoading: modelList.isRefreshing
        ) { modelID in
            settings.setOCRModelID(modelID, for: settings.ocrProviderID)
            isPresented = false
        } onCancel: {
            isPresented = false
        }
    }
}
