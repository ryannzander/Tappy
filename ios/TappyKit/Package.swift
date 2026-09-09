// swift-tools-version: 5.9
import PackageDescription

/// Everything in the iPhone app that can be tested without a phone. The SwiftUI app target
/// depends on this; this depends on nothing but Foundation, CryptoKit and LocalAuthentication,
/// so `swift test` runs it on a Mac with no simulator and no Xcode project.
let package = Package(
    name: "TappyKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "TappyKit", targets: ["TappyKit"]),
        .executable(name: "tappy-verify", targets: ["tappy-verify"]),
    ],
    targets: [
        .target(name: "TappyKit"),
        // The same assertions as TappyKitTests, as an executable, because XCTest needs full
        // Xcode and the frozen vectors need checking on any machine with the command line tools.
        .executableTarget(name: "tappy-verify", dependencies: ["TappyKit"]),
        .testTarget(name: "TappyKitTests", dependencies: ["TappyKit"]),
    ]
)
