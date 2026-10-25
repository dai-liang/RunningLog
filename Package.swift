// swift-tools-version: 6.0
import PackageDescription

// 将统计与校验独立为纯 Swift 模块，便于不启动模拟器也能验证关键逻辑。
let package = Package(
    name: "RunningLogCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "RunCore", targets: ["RunCore"])],
    targets: [
        .target(name: "RunCore", path: "RunningLog/Core"),
        .testTarget(name: "RunCoreTests", dependencies: ["RunCore"], path: "Tests/RunCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
