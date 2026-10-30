// swift-tools-version: 6.0
import PackageDescription

// Tests the actual Foundation-only application models without Apple SDKs.
// The iOS application itself is built from project.yml, with no package dependencies.
let package = Package(
    name: "FennavioState",
    platforms: [.macOS(.v13)],
    products: [.library(name: "FennavioNativePreview", targets: ["FennavioNativePreview"])],
    targets: [
        .target(name: "FennavioNativePreview", path: "FennavioNative/State"),
        .testTarget(name: "FennavioNativeTests", dependencies: ["FennavioNativePreview"], path: "FennavioNativeTests"),
    ]
)
