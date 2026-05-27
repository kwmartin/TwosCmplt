// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "docc-test",
    products: [
        .library(name: "docc-test", targets: ["docc-test"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(name: "docc-test")
    ]
)
