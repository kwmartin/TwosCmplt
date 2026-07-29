// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TwosCmplt",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "TwosCmplt",
            targets: ["TwosCmplt"]),
    ],
    dependencies: [
        // Add the DocC plugin here
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/pvieito/PythonKit.git", branch: "master"),
        .package(
            url: "https://github.com/YusukeHosonuma/SwiftPrettyPrint.git",
            .upToNextMajor(from: "1.2.0")
        ),
        .package(
            url: "https://github.com/apple/swift-configuration",
            from: "1.0.0", traits: [.defaults, "YAML"],
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "SharedTypes"),
        .target(
            name: "TwosCmplt",
            dependencies: [
                "SharedTypes",
                "Yams",
                "SwiftPrettyPrint",
                .product(name: "Configuration", package: "swift-configuration"),
            ],
            path: "Sources/TwosCmplt",
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-strict-concurrency=minimal"
                ])
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .target(
            name: "ExamplesShared",
            dependencies: ["TwosCmplt"],
            path: "Examples/ExamplesShared"
        ),
        .target(
            name: "ExamplesDoc",
            dependencies: [
                .target(name: "TwosCmplt")
            ],
            path: "ExamplesDoc",
            exclude: [
                "Resources/Figures/Filter_3A.png"
            ],
        ),
        .executableTarget(
            name: "CoeffMltply",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/CoeffMltply",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "CmplxMltply",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/CmplxMltply",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "CmplxOsc1",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/CmplxOsc1",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "DigitalExamples",
            dependencies: ["TwosCmplt", "Yams", "SwiftPrettyPrint"],
            path: "Examples/DigitalExamples",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "TwosCmpltTestingRunner",
            dependencies: ["TwosCmplt"],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ]
        ),
        .testTarget(
            name: "TwosCmpltTests",
            dependencies: ["TwosCmplt"],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ]
        ),
        .executableTarget(
            name: "Filter3A",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter3A",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Filter3B",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter3B",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Filter3C",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter3C",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Filter3D",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter3D",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Filter3E",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter3E",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Filter5A",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter5A",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Filter5B",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter5B",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Filter9A",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Filter9A",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "CmplxFilter1A",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/CmplxFilter1A",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "CmplxFilter3E",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/CmplxFilter3E",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "CmplxFilter5B",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/CmplxFilter5B",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Osc1",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Osc1",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Osc2",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Osc2",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Osc3",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Osc3",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Osc4",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Osc4",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Cordic1",
            dependencies: ["TwosCmplt", "Yams", "ExamplesShared"],
            path: "Examples/Cordic1",
            resources: [
                .process("Resources/rotations.dat")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Cordic2",
            dependencies: ["TwosCmplt", "Yams", "ExamplesShared"],
            path: "Examples/Cordic2",
            exclude: [
                "Cordic2.swift_"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Gates",
            dependencies: ["TwosCmplt", "Yams", "ExamplesShared"],
            path: "Examples/Gates",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Circuits",
            dependencies: ["TwosCmplt", "Yams", "ExamplesShared"],
            path: "Examples/Circuits",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "SimRun",
            dependencies: ["TwosCmplt", "Yams", "ExamplesShared"],
            path: "Examples/SimRun",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted")
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
        .executableTarget(
            name: "Interpret",
            dependencies: ["TwosCmplt", "Yams"],
            path: "Examples/Interpret",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=targeted"),
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedLibrary("m") // <--- This adds -lm to linker flags
            ],
        ),
    ]
)
