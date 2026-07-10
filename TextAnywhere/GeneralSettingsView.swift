//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Carbon
import SwiftUI

struct GeneralSettingsView: View {

    let controller: AppController

    @State private var isLanguageMenuPresented = false

    var body: some View {
        Form {
            LabeledContent("Target Language") {
                Button {
                    isLanguageMenuPresented.toggle()
                } label: {
                    HStack {
                        Text(controller.settings.targetLanguage.displayName)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 220)
                }
                .buttonStyle(.bordered)
                .popoverPanel(isPresented: $isLanguageMenuPresented) {
                    LanguageMenuContent(
                        selectedLanguageCode: Binding(
                            get: { controller.settings.targetLanguageCode },
                            set: { controller.settings.targetLanguageCode = $0 }
                        )
                    ) {
                        isLanguageMenuPresented = false
                    }
                    .frame(width: 320, height: 300)
                }
            }

            LabeledContent("Global Shortcut") {
                ShortcutRecorderView(shortcut: controller.settings.shortcut) { shortcut in
                    try controller.updateShortcut(shortcut)
                }
            }

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

            Text("Accessibility access lets TextAnywhere insert a translation into the selected app. Without it, the translation is copied to the clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .fontDesign(.rounded)
    }
}

private struct LanguageMenuContent: View {

    @Binding var selectedLanguageCode: String
    let onSelect: () -> Void

    @State private var searchText = ""
    @State private var highlightedLanguageCode: String?

    private let languages = TranslationLanguage.catalog

    private var filteredLanguages: [TranslationLanguage] {
        guard !searchText.isEmpty else { return languages }
        return languages.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Languages", text: $searchText)
                .textFieldStyle(.plain)
                .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredLanguages) { language in
                        HStack {
                            Text(language.displayName)
                            Spacer()
                            Text(language.code)
                                .foregroundStyle(.secondary)
                            if selectedLanguageCode == language.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            if highlightedLanguageCode == language.code {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.tint.opacity(0.1))
                            }
                        }
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            highlightedLanguageCode = isHovered ? language.code : nil
                        }
                        .onTapGesture {
                            selectedLanguageCode = language.code
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

private struct ShortcutRecorderView: View {

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
            .frame(minWidth: 120)
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

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        configure(nsView)
        guard isRecording else { return }
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func configure(_ view: ShortcutCaptureNSView) {
        view.onKeyDown = { event in
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                return
            }
            do {
                onCapture(try GlobalShortcut(event: event))
                isRecording = false
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}

private final class ShortcutCaptureNSView: NSView {

    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
