// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ABCSheetMusic",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ABCSheetMusic", targets: ["ABCSheetMusic"]),
    ],
    targets: [
        .executableTarget(
            name: "ABCSheetMusic",
            path: "Sources/ABCSheetMusic",
            resources: [
                .copy("Resources/Bridge"),
                .copy("Resources/abcjs"),
                .copy("Resources/coker.abc"),
            ]
        ),
    ]
)