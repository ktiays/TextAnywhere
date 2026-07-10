//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

private enum SettingsPane: Hashable {

    case general
    case provider(ProviderIdentifier)

    var title: String {
        switch self {
        case .general:
            "General"
        case .provider(let identifier):
            Provider.provider(for: identifier).name
        }
    }
}

struct SettingsView: View {

    let controller: AppController

    @State private var selectedPane = SettingsPane.general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            List(selection: $selectedPane) {
                Section {
                    Label("General", systemImage: "gearshape")
                        .tag(SettingsPane.general)
                }

                Section("Providers") {
                    ForEach(Provider.presets) { provider in
                        HStack(spacing: 8) {
                            provider.iconView()
                                .frame(width: 16, height: 16)
                            Text(provider.name)
                            Spacer()
                            Circle()
                                .fill(
                                    controller.settings.isProviderEnabled(provider.id)
                                        ? Color.green
                                        : Color.secondary.opacity(0.25)
                                )
                                .frame(width: 6, height: 6)
                                .accessibilityLabel(
                                    controller.settings.isProviderEnabled(provider.id)
                                        ? "Enabled"
                                        : "Disabled"
                                )
                        }
                        .tag(SettingsPane.provider(provider.id))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text(selectedPane.title)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            selectedDetail
                .formStyle(.grouped)
                .scrollEdgeEffectStyle(.soft, for: .all)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    if case .provider(let identifier) = selectedPane {
                        ToolbarSpacer(.flexible, placement: .primaryAction)
                        ToolbarItem(placement: .primaryAction) {
                            Toggle(
                                "Enabled",
                                isOn: providerEnabledBinding(for: identifier)
                            )
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help("Make this provider available in the translation editor")
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 720)
        .frame(minHeight: 400)
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsView(controller: controller)
        case .provider(let identifier):
            ProvidersPage(
                controller: controller,
                provider: Provider.provider(for: identifier)
            )
        }
    }

    private func providerEnabledBinding(
        for providerID: ProviderIdentifier
    ) -> Binding<Bool> {
        Binding(
            get: { controller.settings.isProviderEnabled(providerID) },
            set: { controller.settings.setProviderEnabled($0, for: providerID) }
        )
    }
}
