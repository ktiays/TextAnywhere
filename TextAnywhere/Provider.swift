//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct Provider: Identifiable, Hashable, Equatable {
    
    let id = UUID()
    let name: String
    let iconAssetName: String?
    let systemImageName: String?

    init(name: String, iconAssetName: String? = nil, systemImageName: String? = nil) {
        self.name = name
        self.iconAssetName = iconAssetName
        self.systemImageName = systemImageName
    }

    @ViewBuilder
    func iconView() -> some View {
        if let iconAssetName {
            Image(iconAssetName)
                .resizable()
                .aspectRatio(1.0, contentMode: .fit)
        } else if let systemImageName {
            Image(systemName: systemImageName)
                .resizable()
                .aspectRatio(1.0, contentMode: .fit)
        } else {
            Image(systemName: "cube")
                .resizable()
                .aspectRatio(1.0, contentMode: .fit)
        }
    }

    static let presets: [Provider] = [
        Provider(name: "Anthropic", iconAssetName: "anthropic"),
        Provider(name: "OpenAI", iconAssetName: "openai"),
        Provider(name: "xAI", iconAssetName: "xai"),
        Provider(name: "OpenRouter", iconAssetName: "openrouter"),
        Provider(name: "百炼大模型", iconAssetName: "bailian"),
    ]
}
