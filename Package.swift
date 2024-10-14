// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "white-tipped-sockets",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "WhiteTippedSockets",
            targets: ["WhiteTipped"]),
//        .executable(
//            name: "WhiteTippedServer",
//            targets: ["WTServer"]),
//        .library(
//            name: "WhiteTippedNIOSockets",
//            targets: ["WTNIOSockets"]),
//        .executable(
//            name: "WhiteTippedNIOServer",
//            targets: ["WTNIOServer"]),
//        .library(
//            name: "WhiteTippedHelpers",
//            targets: ["WTHelpers"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/needle-tail/needletail-logger.git", .upToNextMajor(from: "1.0.4")),
        .package(url: "https://github.com/needle-tail/needletail-algorithms.git", .upToNextMajor(from: "1.0.9")),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.3.0"),
//        .package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "1.0.0")),
//        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.40.0")),
//        .package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from: "2.20.0")),
//        .package(url: "https://github.com/swiftpackages/DotEnv.git", .upToNextMajor(from: "3.0.0")),
//        .package(url: "https://github.com/apple/swift-atomics.git", .upToNextMajor(from: "1.1.0")),
//        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.0.4"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "WhiteTipped",
            dependencies: [
                "WTHelpers",
                .product(name: "NeedleTailLogger", package: "needletail-logger"),
                .product(name: "NeedleTailAlgorithms", package: "needletail-algorithms"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")
            ]),
//        .target(
//            name: "WhiteTippedListener",
//            dependencies: ["WTHelpers"]),
//        .executableTarget(
//            name: "WTServer",
//            dependencies: ["WhiteTippedListener"]),
//        .target(name: "WTNIOSockets",
//                dependencies: [
//                    .product(name: "NIO", package: "swift-nio"),
//                    .product(name: "NIOHTTP1", package: "swift-nio"),
//                    .product(name: "NIOWebSocket", package: "swift-nio"),
//                    .product(name: "NIOSSL", package: "swift-nio-ssl"),
//                    .product(name: "DotEnv", package: "DotEnv"),
//                    "WTHelpers"
//                ]),
//        .executableTarget(
//            name: "WTNIOServer",
//            dependencies: ["WTNIOSockets"]),
        .testTarget(
            name: "WhiteTippedTests",
            dependencies: [
                "WhiteTipped",
                "WTHelpers"
            ]),
        .target(
            name: "WTHelpers",
            dependencies: [
                .product(name: "NeedleTailLogger", package: "needletail-logger")
//                .product(name: "Atomics", package: "swift-atomics"),
//                .product(name: "DequeModule", package: "swift-collections")
            ])
    ]
)
