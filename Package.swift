// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KiteSim",
    // iOS 26 是硬性最低版本：Liquid Glass（glassEffect / GlassEffectContainer /
    // .glass / .glassProminent）都是 iOS 26.0+ 才有的 API。
    // .iOS(.v26) 需要 SwiftPM 6.2+，而 xtool 要求 Swift 6.4，满足。
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        // xtool 要求恰好一个 library product，代表主 App
        .library(
            name: "KiteSim",
            targets: ["KiteSim"]
        ),
    ],
    dependencies: [
        // 微软官方 ONNX Runtime SwiftPM 包（含 iOS XCFramework 二进制）。
        // 用于原样复用 ddddocr 的 common_old.onnx，不需要重新训练或转 Core ML。
        .package(
            url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
            from: "1.24.2"
        ),
    ],
    targets: [
        .target(
            name: "KiteSim",
            dependencies: [
                .product(
                    name: "onnxruntime",
                    package: "onnxruntime-swift-package-manager"
                ),
            ],
            resources: [
                // 用 .copy 保持二进制模型字节不变（.process 可能会改写资源）
                .copy("Resources/common_old.onnx"),
                .copy("Resources/charset.json"),
            ]
        ),
    ],
    // 以 Swift 5 语言模式编译：避免 Swift 6 严格并发检查把大量 UI/回调代码
    // 一次性推倒重来；运行时仍是 Swift 6.4 工具链 + Xcode 27 (iOS 26+) SDK。
    swiftLanguageModes: [.v5]
)
