// swift-tools-version: 6.2
//
//  Created by ktiays on 2026/10/23.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "MarkdownEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"]),
    ],
    targets: [
        .target(
            name: "CMD4C",
            exclude: ["LICENSE.md"]
        ),
        .target(
            name: "MarkdownEngine",
            dependencies: ["CMD4C"]
        ),
        .testTarget(
            name: "MarkdownEngineTests",
            dependencies: ["MarkdownEngine"],
            resources: [.copy("Golden")]
        ),
    ],
    cxxLanguageStandard: .gnucxx20
)
