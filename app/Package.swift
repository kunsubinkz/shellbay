// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Shellbay",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.13.0"),
    ],
    targets: [
        .target(name: "ShellbayCore"),
        .executableTarget(
            name: "Shellbay",
            dependencies: [
                "ShellbayCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(name: "ShellbayTests", dependencies: ["ShellbayCore"]),
    ]
)
