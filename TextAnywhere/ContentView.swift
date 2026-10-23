//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @Bindable var session: TranslationSession

    @State private var editorHasMarkedText = false
    @State private var isImageDropTargeted = false
    @State private var isFileImporterPresented = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                targetApplicationMenu
                Spacer()
                if #available(macOS 27, *) {
                    markdownRenderingPicker
                        .padding(.trailing, 8)
                }
                targetLanguageMenu
            }

            ZStack(alignment: .topLeading) {
                MarkdownTextEditor(
                    text: $session.draft,
                    isEditable: session.isEditable,
                    rendersMarkdown: session.isMarkdownRenderingEnabled,
                    focusRequestID: session.focusRequestID
                ) { hasMarkedText in
                    editorHasMarkedText = hasMarkedText
                } onPaste: {
                    session.recognizePastedContent()
                } onEscape: {
                    session.handleEscape()
                }

                if session.draft.isEmpty && !editorHasMarkedText {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if session.isPasteAndDropOCRAvailable {
                    ImageDropTarget { isTargeted in
                        isImageDropTargeted = isTargeted
                    } onDrop: { source in
                        session.recognizeText(from: source)
                    }
                }
            }
            .overlay {
                if isImageDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                }
            }

            if case .message(let message, let isError) = session.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if isRecording {
                    AudioWaveformView(
                        levels: session.voiceInput.levels,
                        lastLevelDate: session.voiceInput.lastLevelDate
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                } else if session.voiceInput.isActive || session.isRecognizingText {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(activityDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    providerMenu
                    Spacer()
                }
                if session.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
                if session.isScreenCaptureOCRAvailable && !session.voiceInput.isActive {
                    iconButton(systemImage: "text.viewfinder", label: "Recognize Text on Screen") {
                        session.requestScreenCapture()
                    }
                    .help("Select an area of the screen to recognize its text")
                    .disabled(!session.canStartTextRecognition)
                }
                if session.isFilePickerOCRAvailable && !session.voiceInput.isActive {
                    iconButton(systemImage: "photo.on.rectangle", label: "Recognize Text in File") {
                        isFileImporterPresented = true
                    }
                    .help("Choose an image or PDF to recognize its text")
                    .disabled(!session.canStartTextRecognition)
                }
                if session.isVoiceInputAvailable || session.voiceInput.isActive {
                    Button {
                        session.toggleVoiceInput()
                    } label: {
                        ZStack {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(Color.primary)
                                .scaleEffect(isRecording ? 0.01 : 1)
                                .opacity(isRecording ? 0 : 1)
                            Image(systemName: "stop.fill")
                                .foregroundStyle(Color.red)
                                .scaleEffect(isRecording ? 1 : 0.01)
                                .opacity(isRecording ? 1 : 0)
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRecording ? "Stop and Transcribe" : "Start Voice Input")
                    .help(isRecording ? "Stop and transcribe recording (Esc to cancel)" : "Start voice input")
                    .disabled(!session.canStartVoiceInput && !isRecording)
                }
                if !isRecording {
                    Group {
                        if session.isTranslationButtonVisible && !session.voiceInput.isActive {
                            Button("Translate") {
                                session.translate()
                            }
                            .disabled(!session.canTranslate)
                        }
                        Button(session.primaryButtonTitle) {
                            session.performPrimaryAction()
                        }
                        .disabled(!session.canPerformPrimaryAction)
                    }
                    .transition(.opacity.animation(.spring(duration: 0.15)))
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.15), value: session.voiceInput.phase)
        }
        .padding(16)
        .padding(.top, 8)
        .fontDesign(.rounded)
        .background(.regularMaterial)
        .background {
            CommandEnterMonitor(
                isEnabled: session.canPerformPrimaryAction,
                onEscape: session.voiceInput.isActive || session.isRecognizingText
                    ? { session.handleEscape() }
                    : nil
            ) {
                session.performPrimaryAction()
            }
            .allowsHitTesting(false)
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.image, .pdf]) { result in
            switch result {
            case .success(let url):
                session.recognizeText(from: .fileURL(url))
            case .failure(let error):
                session.showError(error.localizedDescription)
            }
        }
        .onExitCommand {
            session.handleEscape()
        }
    }

    private var isRecording: Bool {
        session.voiceInput.phase == .recording
    }

    private var placeholder: String {
        session.isPasteAndDropOCRAvailable ? "Type text, or paste or drop an image…" : "Type text to translate…"
    }

    @available(macOS 27, *)
    private var markdownRenderingPicker: some View {
        Picker("Editor Mode", selection: $session.isMarkdownRenderingEnabled) {
            Label("Plain Text", systemImage: "doc.plaintext")
                .labelStyle(.iconOnly)
                .tag(false)
            Label("Markdown", systemImage: "doc.richtext")
                .labelStyle(.iconOnly)
                .tag(true)
        }
        .pickerStyle(.tabs)
        .buttonBorderShape(.capsule)
        .labelsHidden()
        .fixedSize()
        .help("Choose whether to edit as plain text or with Markdown rendering")
    }

    private var activityDescription: String {
        if session.isTranslatingRecognizedText {
            "Translating…"
        } else if session.isRecognizingText {
            "Recognizing text…"
        } else if session.voiceInput.phase == .transcribing {
            "Transcribing…"
        } else {
            "Requesting microphone access…"
        }
    }

    private func iconButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.primary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ContentBuilder
    private var targetLanguageMenu: some View {
        Menu {
            ForEach(TargetLanguageMode.allCases) { mode in
                Button {
                    session.selectTargetLanguageMode(mode)
                } label: {
                    HStack {
                        Text(title(for: mode))
                        if session.targetLanguageMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                if mode == .automatic {
                    Divider()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                if session.targetLanguageMode == .automatic {
                    Text(session.detectedLanguage?.displayName ?? "Auto")
                    Image(systemName: "arrow.right")
                        .imageScale(.small)
                }
                Text(session.targetLanguage.displayName)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .lineLimit(1)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Choose the target language")
    }

    private func title(for mode: TargetLanguageMode) -> String {
        switch mode {
        case .automatic:
            "Automatic (\(session.languagePair.primary.displayName) ⇄ \(session.languagePair.secondary.displayName))"
        case .primary:
            session.languagePair.primary.displayName
        case .secondary:
            session.languagePair.secondary.displayName
        }
    }

    @ContentBuilder
    private var providerMenu: some View {
        Menu {
            if session.enabledProviders.isEmpty {
                Text("No Providers Enabled")
            } else {
                Picker("Provider", selection: providerSelection) {
                    ForEach(session.enabledProviders) { provider in
                        Text(provider.name)
                            .tag(provider)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            Group {
                if session.enabledProviders.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(Color.red)
                } else {
                    session.selectedProvider.iconView()
                }
            }
            .frame(width: 16, height: 16)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(providerMenuDescription)
        .help(providerMenuDescription)
    }

    private var providerSelection: Binding<Provider> {
        Binding {
            session.selectedProvider
        } set: { provider in
            session.selectProvider(provider)
        }
    }

    private var providerMenuDescription: String {
        if session.enabledProviders.isEmpty {
            "No Provider Enabled"
        } else {
            "\(session.selectedProvider.name) · \(session.selectedModelID)"
        }
    }

    @ContentBuilder
    private var targetApplicationMenu: some View {
        Menu {
            if session.runningApplications.isEmpty {
                Text("No Applications")
            } else {
                ForEach(session.runningApplications) { application in
                    Button {
                        session.selectTarget(application)
                    } label: {
                        Label {
                            HStack {
                                Text(application.localizedName)
                                if session.selectedTarget == application {
                                    Image(systemName: "checkmark")
                                }
                            }
                        } icon: {
                            if let icon = application.icon {
                                Image(nsImage: icon)
                            } else {
                                Image(systemName: "macwindow")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = session.selectedTarget?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "macwindow")
                }
                Text(session.selectedTarget?.localizedName ?? "Choose App")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct AudioWaveformView: View {
    let levels: [Float]
    let lastLevelDate: Date

    private let spacing: CGFloat = 5
    private let barWidth: CGFloat = 2
    private let edgeFadeWidth: CGFloat = 12
    private let growthSpring = Spring(duration: 0.2, bounce: 0.2)
    private let shrinkSpring = Spring(duration: 0.2)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // Fraction of the metering interval elapsed since the newest sample, used to
                // scroll bars continuously between samples instead of stepping once per sample.
                let elapsed = timeline.date.timeIntervalSince(lastLevelDate) / VoiceInput.meteringInterval
                let progress = CGFloat(min(1, max(0, elapsed)))
                let slotCount = Int(size.width / spacing) + 2
                for slot in 0..<slotCount {
                    let age = CGFloat(slot) + progress
                    let x = size.width - barWidth - age * spacing
                    guard x > 0 else { break }
                    // Sample springs at the bar's age for the grow-in, and at its progress through
                    // the edge region for the shrink-out, so both follow spring curves.
                    let growthTime = Double(age) * VoiceInput.meteringInterval
                    let growth: CGFloat = growthSpring.value(target: 1, time: growthTime)
                    let fadeFraction = Double(max(0, edgeFadeWidth - x) / edgeFadeWidth)
                    let fadeTime = fadeFraction * shrinkSpring.settlingDuration
                    let edgeScale = max(0, 1 - shrinkSpring.value(target: CGFloat(1), time: fadeTime))
                    let sampleIndex = levels.count - 1 - slot
                    let level = sampleIndex >= 0 ? CGFloat(levels[sampleIndex]) : 0
                    let fullHeight = max(barWidth, level * size.height)
                    let height = (barWidth + (fullHeight - barWidth) * growth) * edgeScale
                    let width = barWidth * edgeScale
                    let rect = CGRect(
                        x: x + (barWidth - width) / 2,
                        y: (size.height - height) / 2,
                        width: width,
                        height: height
                    )
                    context.fill(Capsule().path(in: rect), with: .style(.primary))
                }
            }
        }
        .accessibilityLabel("Recording audio. Press Escape to cancel.")
    }
}
