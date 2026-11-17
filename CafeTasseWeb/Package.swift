// swift-tools-version: 6.0
import PackageDescription

// WebAssembly build of a reduced CafeTasse: café list, café detail with check-in and photo,
// visit history. Build with ./build.sh, see README.md.
let package = Package(
    name: "CafeTasseWeb",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", exact: "0.63.0"),
        .package(path: "../CafeTasseCore")
    ],
    targets: [
        .executableTarget(
            name: "CafeTasseWeb",
            dependencies: [
                "JavaScriptKit",
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
                .product(name: "CafeTasseCore", package: "CafeTasseCore")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
