//
//  Created by ktiays on 2026/9/24.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import SwiftUI

struct VoiceInputSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextField("Model Name", text: $settings.transcriptionModel)
            } footer: {
                Text("Voice input requires Bailian to be enabled and its API key configured in Providers → Bailian. The microphone is hidden until Bailian is configured.")
            }
        }
    }
}
