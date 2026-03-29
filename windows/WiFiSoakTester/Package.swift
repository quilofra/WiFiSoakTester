// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WiFiSoakTester",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WiFiSoakTester", targets: ["WiFiSoakTester"])
    ],
    targets: [
        .executableTarget(
            name: "WiFiSoakTester",
            path: "Sources/WiFiSoakTester"
        ),
        .testTarget(
            name: "WiFiSoakTesterTests",
            dependencies: ["WiFiSoakTester"],
            path: "Tests/WiFiSoakTesterTests"
        )
    ]
)
