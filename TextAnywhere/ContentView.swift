//
//  Created by ktiays on 2026/4/15.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

#Preview {
    ContentView()
}
