// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhosphorusWriter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PhosphorusWriter", targets: ["PhosphorusWriter"])],
    targets: [
        .target(name: "WriterCore"),
        .executableTarget(name: "PhosphorusWriter", dependencies: ["WriterCore"]),
        .testTarget(name: "WriterCoreTests", dependencies: ["WriterCore"])
    ]
)
