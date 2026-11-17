// swift-tools-version: 6.0
import PackageDescription

// Pure-Swift core shared by the iOS app and the WebAssembly web app.
// Must not import SwiftData, SwiftUI, UIKit, CoreLocation or any other Apple-only framework.
let package = Package(
    name: "CafeTasseCore",
    products: [
        .library(name: "CafeTasseCore", targets: ["CafeTasseCore"])
    ],
    targets: [
        .target(name: "CafeTasseCore"),
        .testTarget(name: "CafeTasseCoreTests", dependencies: ["CafeTasseCore"])
    ]
)
