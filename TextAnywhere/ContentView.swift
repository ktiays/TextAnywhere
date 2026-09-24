//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import SwiftUI

struct ContentView: View {

    @Bindable var session: TranslationSession

    @FocusState private var editorFocused: Bool
    @State private var editorHasMarkedText = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                targetApplicationMenu
                Spacer()
                Label(session.targetLanguage.displayName, systemImage: "globe")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $session.draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .disabled(session.isTranslating || session.voiceInput.isActive)

                if session.draft.isEmpty && !editorHasMarkedText {
                    Text("Type text to translate…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
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
                if session.voiceInput.phase == .recording {
                    AudioWaveformView(levels: session.voiceInput.levels)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                } else if session.voiceInput.isActive {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(session.voiceInput.phase == .transcribing ? "Transcribing…" : "Requesting microphone access…")
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
                if session.isTranslationButtonVisible && !session.voiceInput.isActive {
                    Button("Translate") {
                        session.translate()
                    }
                    .disabled(!session.canTranslate)
                }
                if session.isVoiceInputAvailable || session.voiceInput.isActive {
                    Button {
                        session.toggleVoiceInput()
                    } label: {
                        Image(systemName: session.voiceInput.phase == .recording ? "stop.fill" : "mic.fill")
                            .foregroundStyle(session.voiceInput.phase == .recording ? Color.red : Color.primary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.voiceInput.phase == .recording ? "Stop and Transcribe" : "Start Voice Input")
                    .help(session.voiceInput.phase == .recording ? "Stop and transcribe recording (Esc to cancel)" : "Start voice input")
                    .disabled(!session.canStartVoiceInput && session.voiceInput.phase != .recording)
                }
                Button(session.primaryButtonTitle) {
                    session.performPrimaryAction()
                }
                .disabled(!session.canPerformPrimaryAction)
            }
        }
        .padding(16)
        .padding(.top, 8)
        .fontDesign(.rounded)
        .background(.regularMaterial)
        .onAppear {
            editorFocused = true
        }
        .onChange(of: session.focusRequestID) {
            editorFocused = true
        }
        .background {
            CommandEnterMonitor(
                isEnabled: session.canPerformPrimaryAction,
                onEscape: session.voiceInput.isActive ? { session.handleEscape() } : nil
            ) {
                session.performPrimaryAction()
            }
            .allowsHitTesting(false)
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: NSTextView.didChangeSelectionNotification) {
                guard let textView = notification.object as? NSTextView,
                      textView.window?.firstResponder === textView else {
                    continue
                }
                editorHasMarkedText = textView.hasMarkedText()
            }
        }
        .onExitCommand {
            session.handleEscape()
        }
    }

    @ContentBuilder
    private var providerMenu: some View {
        Menu {
            if session.enabledProviders.isEmpty {
                Text("No Providers Enabled")
            } else {
                ForEach(session.enabledProviders) { provider in
                    Button {
                        session.selectProvider(provider)
                    } label: {
                        HStack {
                            Text(provider.name)
                            if session.selectedProvider == provider {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if session.enabledProviders.isEmpty {
                    Text("No Provider Enabled")
                } else {
                    HStack(spacing: 5) {
                        Text(session.selectedProvider.name)
                        Circle()
                            .frame(width: 3, height: 3)
                        Text(session.selectedModelID)
                    }
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(session.enabledProviders.isEmpty ? Color.red : Color.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
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

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 5
            let count = max(1, Int(size.width / spacing))
            let visibleLevels = Array(levels.suffix(count))
            let leadingCount = count - visibleLevels.count
            for index in 0..<count {
                let level = index < leadingCount ? 0 : CGFloat(visibleLevels[index - leadingCount])
                let height = max(2, level * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * spacing,
                    y: (size.height - height) / 2,
                    width: 2,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(.white)
                )
            }
        }
        .accessibilityLabel("Recording audio. Press Escape to cancel.")
    }
}
