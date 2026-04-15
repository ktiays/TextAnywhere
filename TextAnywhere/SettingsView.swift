//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    
    var body: some View {
        TabView {
            ProvidersPage()
                .tabItem {
                    Label("Providers", systemImage: "laser.burst")
                }
        }
        .frame(width: 480, height: 320)
    }
}

#Preview {
    SettingsView()
}
