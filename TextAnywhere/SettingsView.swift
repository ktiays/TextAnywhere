//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct SettingsView: View {

    let controller: AppController

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ProvidersPage(controller: controller)
                .tabItem {
                    Label("Providers", systemImage: "laser.burst")
                }
        }
        .frame(width: 560, height: 420)
    }
}
