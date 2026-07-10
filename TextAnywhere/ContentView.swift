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
                    .disabled(session.isTranslating)

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
                Text(providerDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if session.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Send") {
                    session.submit()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!session.canSubmit)
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
        .task {
            for await notification in NotificationCenter.default.notifications(
                named: NSTextView.didChangeSelectionNotification
            ) {
                guard let textView = notification.object as? NSTextView,
                      textView.window?.firstResponder === textView else {
                    continue
                }
                editorHasMarkedText = textView.hasMarkedText()
            }
        }
        .onExitCommand {
            session.dismiss()
        }
    }

    private var providerDescription: String {
        let modelID = session.selectedModelID
        return modelID.isEmpty
            ? session.selectedProvider.name
            : "\(session.selectedProvider.name) · \(modelID)"
    }

    private var targetApplicationMenu: some View {
        Menu {
            if session.runningApplications.isEmpty {
                Text("No Applications")
            } else {
                ForEach(session.runningApplications) { application in
                    Button {
                        session.selectTarget(application)
                    } label: {
                        Text(application.localizedName)
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
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
