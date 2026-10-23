//
// Created by ktiays on 2026/10/22.
// Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct OCRSettingsView: View {

    let controller: AppController

    @State private var shortcutErrorMessage: String?

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

                LabeledContent("Model") {
                    Picker(
                        "Model",
                        selection: Binding(
                            get: { settings.ocrModel },
                            set: { model in
                                settings.ocrModel = model
                                controller.session.refreshCredentialAvailability()
                            }
                        )
                    ) {
                        ForEach(OCRModel.allCases) { model in
                            Text("\(model.displayName) (\(model.provider.name))")
                                .tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }
                .disabled(!settings.isOCREnabled)
            } footer: {
                Text("\(settings.ocrModel.displayName) requires \(settings.ocrModel.provider.name) to be enabled and its API key configured in Providers → \(settings.ocrModel.provider.name). OCR stays hidden in the editor until then.")
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
    }

    private var settings: AppSettings {
        controller.settings
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
