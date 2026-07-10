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
    @State private var isTargetApplicationMenuPresented = false

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
                providerMenu

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
                            Text(providerMenuLabel(for: provider))
                            if session.selectedProvider == provider {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(session.enabledProviders.isEmpty ? "No Provider Enabled" : providerDescription)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(session.enabledProviders.isEmpty ? Color.red : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func providerMenuLabel(for provider: Provider) -> String {
        let modelID = session.modelID(for: provider)
        return modelID.isEmpty ? provider.name : "\(provider.name) · \(modelID)"
    }

    private var targetApplicationMenu: some View {
        Button {
            isTargetApplicationMenuPresented.toggle()
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
        .buttonStyle(.plain)
        .popoverPanel(isPresented: $isTargetApplicationMenuPresented) {
            TargetApplicationMenuContent(
                applications: session.runningApplications,
                selectedApplication: session.selectedTarget
            ) { application in
                session.selectTarget(application)
                isTargetApplicationMenuPresented = false
            }
            .frame(width: 320, height: 280)
        }
        .fixedSize()
    }
}

private struct TargetApplicationMenuContent: View {

    let applications: [TargetApplication]
    let selectedApplication: TargetApplication?
    let onSelect: (TargetApplication) -> Void

    @FocusState private var searchFieldFocused: Bool
    @State private var searchText = ""
    @State private var highlightedApplicationID: pid_t?

    private var filteredApplications: [TargetApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return applications }
        return applications.filter { application in
            application.localizedName.localizedCaseInsensitiveContains(query)
                || application.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Applications", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .padding()

            Divider()

            if filteredApplications.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredApplications) { application in
                            applicationRow(application)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .fontDesign(.rounded)
        .onAppear {
            searchFieldFocused = true
        }
    }

    private func applicationRow(_ application: TargetApplication) -> some View {
        HStack(spacing: 8) {
            if let icon = application.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "macwindow")
                    .frame(width: 18, height: 18)
            }

            Text(application.localizedName)
                .lineLimit(1)

            Spacer()

            if selectedApplication == application {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if highlightedApplicationID == application.id {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.tint.opacity(0.1))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            highlightedApplicationID = isHovered ? application.id : nil
        }
        .onTapGesture {
            onSelect(application)
        }
    }
}
