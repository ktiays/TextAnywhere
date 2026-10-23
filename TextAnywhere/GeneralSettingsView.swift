//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon
import SwiftUI

struct GeneralSettingsView: View {

    let controller: AppController

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Global Shortcut")
                    Spacer()
                    ShortcutRecorderView(shortcut: controller.settings.shortcut) { shortcut in
                        try controller.updateShortcut(shortcut)
                    }
                }
                Toggle(
                    "Show in Menu Bar",
                    isOn: Binding(
                        get: { controller.settings.isTrayEnabled },
                        set: { controller.settings.isTrayEnabled = $0 }
                    )
                )
            }

            Section {
                LabeledContent {
                    LanguagePickerButton(language: languagePair.primary) { code in
                        controller.settings.setPrimaryLanguageCode(code)
                    }
                } label: {
                    Text("Primary Language")
                    Text("Used when the input language can't be matched.")
                }

                LabeledContent {
                    LanguagePickerButton(language: languagePair.secondary) { code in
                        controller.settings.setSecondaryLanguageCode(code)
                    }
                } label: {
                    Text("Secondary Language")
                }

                LabeledContent("Target Language") {
                    Picker(
                        "Target Language",
                        selection: Binding(
                            get: { controller.settings.targetLanguageMode },
                            set: { controller.settings.targetLanguageMode = $0 }
                        )
                    ) {
                        Text("Automatic")
                            .tag(TargetLanguageMode.automatic)
                        Divider()
                        Text(languagePair.primary.displayName)
                            .tag(TargetLanguageMode.primary)
                        Text(languagePair.secondary.displayName)
                            .tag(TargetLanguageMode.secondary)
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }
            } header: {
                Text("Translation")
            } footer: {
                Text("Automatic detects the input language. \(languagePair.primary.displayName) is translated into \(languagePair.secondary.displayName), and everything else, including text that can't be recognized, into \(languagePair.primary.displayName). You can also switch the target in the editor.")
            }

            Section {
                Toggle(
                    "Show Translation Button",
                    isOn: Binding(
                        get: { controller.settings.isTranslationButtonVisible },
                        set: { controller.settings.isTranslationButtonVisible = $0 }
                    )
                )

                LabeledContent("Primary Button") {
                    Picker(
                        "Primary Button",
                        selection: Binding(
                            get: { controller.settings.primaryButtonAction },
                            set: { controller.settings.primaryButtonAction = $0 }
                        )
                    ) {
                        ForEach(EditorAction.primaryButtonOptions) { action in
                            Text(action.displayName)
                                .tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220, alignment: .trailing)
                }
            } header: {
                Text("Editor")
            } footer: {
                Text("⌘ + Enter triggers the primary button.")
            }

            Section {
                LabeledContent("Accessibility") {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if controller.insertionService.isTrusted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Grant Access") {
                                controller.insertionService.requestPermission()
                            }
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility access lets TextAnywhere insert a translation into the selected app. Without it, the translation is copied to the clipboard.")
            }

            Section {
                Toggle(
                    "Check for Updates Automatically",
                    isOn: Binding(
                        get: { controller.settings.isAutomaticUpdateCheckEnabled },
                        set: { controller.settings.isAutomaticUpdateCheckEnabled = $0 }
                    )
                )

                LabeledContent {
                    Button("Check Now") {
                        updateController.checkForUpdates()
                    }
                    .disabled(updateController.isBusy)
                } label: {
                    Text("Version \(updateController.currentVersionDescription)")
                    Text(updateStatus)
                }
            } header: {
                Text("Updates")
            }
        }
        .fontDesign(.rounded)
    }

    private var languagePair: LanguagePair {
        controller.settings.languagePair
    }

    private var updateController: UpdateController {
        controller.updateController
    }

    private var updateStatus: String {
        switch updateController.activity {
        case .checking:
            return "Checking for updates…"
        case .installing:
            return "Installing update…"
        case .idle:
            guard let lastCheckDate = updateController.lastCheckDate else {
                return "Never checked"
            }
            return "Last checked \(lastCheckDate.formatted(date: .abbreviated, time: .shortened))"
        }
    }
}

private struct LanguagePickerButton: View {

    let language: TranslationLanguage
    let onSelect: (String) -> Void

    @State private var isMenuPresented = false

    var body: some View {
        Button {
            isMenuPresented.toggle()
        } label: {
            HStack {
                Text(language.displayName)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220)
        }
        .buttonStyle(.bordered)
        .popoverPanel(isPresented: $isMenuPresented) {
            SearchableMenu(
                items: TranslationLanguage.menuItems,
                selectedID: language.code,
                searchPrompt: "Search Languages"
            ) { code in
                onSelect(code)
                isMenuPresented = false
            } onCancel: {
                isMenuPresented = false
            }
            .frame(width: 320, height: 300)
        }
    }
}

private extension TranslationLanguage {

    static let menuItems: [SearchableMenuItem] = {
        let englishLocale = Locale(identifier: "en")
        return catalog.map { language in
            SearchableMenuItem(
                id: language.code,
                title: language.displayName,
                detail: language.code,
                searchTerms: [
                    language.code,
                    englishLocale.localizedString(forLanguageCode: language.code),
                    Locale(identifier: language.code).localizedString(forLanguageCode: language.code),
                ].compactMap(\.self)
            )
        }
    }()
}

struct ShortcutRecorderView: View {

    let shortcut: GlobalShortcut
    let onChange: (GlobalShortcut) throws -> Void

    @State private var isRecording = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(isRecording ? "Type Shortcut…" : shortcut.displayName) {
                errorMessage = nil
                isRecording = true
            }
            .frame(minWidth: 120, alignment: .trailing)
            .background {
                ShortcutCaptureView(isRecording: $isRecording) { capturedShortcut in
                    do {
                        try onChange(capturedShortcut)
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } onError: { message in
                    errorMessage = message
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {

    @Binding var isRecording: Bool
    let onCapture: (GlobalShortcut) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            hostView: nsView,
            isRecording: isRecording
        ) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                return true
            }
            do {
                onCapture(try GlobalShortcut(event: event))
                isRecording = false
                return true
            } catch {
                onError(error.localizedDescription)
                return false
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {

        private weak var hostView: NSView?
        private var eventMonitor: Any?
        private var onKeyDown: ((NSEvent) -> Bool)?

        func update(
            hostView: NSView,
            isRecording: Bool,
            onKeyDown: @escaping (NSEvent) -> Bool
        ) {
            self.hostView = hostView
            self.onKeyDown = onKeyDown

            if isRecording {
                start()
            } else {
                stop()
            }
        }

        func stop() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            onKeyDown = nil
        }

        private func start() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      event.window === hostView?.window,
                      let onKeyDown else {
                    return event
                }

                if onKeyDown(event) {
                    stop()
                }
                return nil
            }
        }
    }
}
