//
//  Created by ktiays on 2026/7/14.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

enum EditorAction: String, CaseIterable, Identifiable {

    case paste
    case translateAndPaste

    static let primaryButtonOptions: [EditorAction] = [
        .paste,
        .translateAndPaste,
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paste:
            "Paste"
        case .translateAndPaste:
            "Translate and Paste"
        }
    }
}
