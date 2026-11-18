// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "screen-annotator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "annotate", targets: ["annotate"])
    ],
    targets: [
        .executableTarget(
            name: "annotate",
            path: "Sources/annotate"
        )
    ]
)
