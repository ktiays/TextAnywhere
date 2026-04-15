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
                            content: ProviderMenuContent(),
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

    private var providerPickerContent: some View {
        VStack(spacing: 0) {
            TextField("Search provider", text: $searchProviderKeyword)
                .textFieldStyle(.roundedBorder)
                .padding()

            Divider()

            List(filteredProviders) { provider in
                Button {
                    selectedProvider = provider
                    popoverPresenter.dismiss()
                } label: {
                    HStack(spacing: 8) {
                        provider.iconView()
                            .frame(width: 16, height: 16)
                        Text(provider.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 120)
        }
        .frame(width: 240)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

private struct ProviderMenuContent: View {
    
    @State private var searchKeyword: String = ""
    
    var body: some View {
        TextField(text: $searchKeyword) {
            
        }
    }
}

#Preview {
    ProvidersPage()
        .frame(minWidth: 400)
}
