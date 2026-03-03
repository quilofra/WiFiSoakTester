// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WiFiSoakTester",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WiFiSoakTester", targets: ["WiFiSoakTester"]),
        .executable(name: "WiFiSoakTesterLinux", targets: ["WiFiSoakTesterLinux"])
    ],
    targets: [
        .executableTarget(
            name: "WiFiSoakTester",
            path: "Sources/WiFiSoakTester",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "WiFiSoakTesterLinux",
            path: "Sources/WiFiSoakTesterLinux"
        ),
        .testTarget(
            name: "WiFiSoakTesterTests",
            dependencies: ["WiFiSoakTester"],
            path: "Tests/WiFiSoakTesterTests"
        )
    ]
)
