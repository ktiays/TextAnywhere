//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct ProvidersPage: View {

    @State private var searchProviderKeyword: String = ""
    @State private var selectedProvider: Provider = Provider.presets[0]
    @State private var popoverPresenter = PopoverPanelPresenter()
    @State private var buttonView: NSView?

    private var filteredProviders: [Provider] {
        if searchProviderKeyword.isEmpty {
            return Provider.presets
        }
        return Provider.presets.filter {
            $0.name.localizedCaseInsensitiveContains(searchProviderKeyword)
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                HStack(spacing: 12) {
                    Text("AI Provider")
                        .foregroundStyle(.secondary)
                    Button {
                        guard let buttonView = buttonView else {
                            return
                        }
                        popoverPresenter.present(
                            content: {
                                ProviderMenuContent(selectedProvider: $selectedProvider)
                                    .frame(maxWidth: 320, maxHeight: 280)
                            },
                            relativeTo: buttonView
                        )
                    } label: {
                        HStack {
                            selectedProvider.iconView()
                                .frame(height: 16)
                            Text(selectedProvider.name)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(style: .init(lineWidth: 1, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(.quaternary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popoverAnchor($buttonView)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fontDesign(.rounded)
    }
}

private struct ProviderMenuContent: View {

    @Binding var selectedProvider: Provider
    @State private var searchKeyword: String = ""
    
    @State private var highlightedProvider: Provider?

    init(selectedProvider: Binding<Provider>) {
        _selectedProvider = selectedProvider
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $searchKeyword, prompt: Text("Search")) {

            }
            .textFieldStyle(.plain)
            .padding(10)
            Divider()
            List {
                ForEach(Provider.presets) { provider in
                    HStack {
                        provider.iconView()
                            .frame(height: 16)
                        Text(provider.name)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background {
                        if highlightedProvider == provider {
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundStyle(.accent)
                                .opacity(0.1)
                        }
                    }
                    .onHover { isHover in
                        if isHover {
                            highlightedProvider = provider
                        }
                    }
                    .onTapGesture {
                        selectedProvider = provider
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .fontDesign(.rounded)
    }
}

#Preview {
    ProvidersPage()
        .frame(minWidth: 400)
}

#Preview {
    @Previewable @State var selectedProvider: Provider = Provider.presets[0]
    ProviderMenuContent(selectedProvider: $selectedProvider)
}
