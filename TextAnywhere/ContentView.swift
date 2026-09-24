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
                if isRecording {
                    AudioWaveformView(
                        levels: session.voiceInput.levels,
                        lastLevelDate: session.voiceInput.lastLevelDate
                    )
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

    private var isRecording: Bool {
        session.voiceInput.phase == .recording
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
