// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

extension Target.Dependency {
    static var concurrencyExtras: Self {
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
    }
    static var customDump: Self {
        .product(name: "CustomDump", package: "swift-custom-dump")
    }
    static var dependencies: Self {
        .product(name: "Dependencies", package: "swift-dependencies")
    }
    static var dependenciesMacros: Self {
        .product(name: "DependenciesMacros", package: "swift-dependencies")
    }
    static var dependenciesTestSupport: Self {
        .product(name: "DependenciesTestSupport", package: "swift-dependencies")
    }
    static var keychainSwift: Self {
        .product(name: "KeychainSwift", package: "keychain-swift")
    }
    static var sharing: Self {
        .product(name: "Sharing", package: "swift-sharing")
    }
}

let package = Package(
    name: "swift-keychain-service",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(
            name: "KeychainService",
            targets: ["KeychainService"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/pointfreeco/swift-sharing", .upToNextMajor(from: "2.8.1")),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/evgenyneu/keychain-swift.git", .upToNextMajor(from: "24.0.0")),
    ],
    targets: [
        .target(
            name: "KeychainService",
            dependencies: [
                .concurrencyExtras,
                .dependencies,
                .dependenciesMacros,
                .keychainSwift,
                .sharing
            ]
        ),
        .testTarget(
            name: "KeychainServiceTests",
            dependencies: [
                "KeychainService",
                .concurrencyExtras,
                .customDump,
                .dependencies,
                .dependenciesTestSupport,
                .sharing
            ]
        ),
    ]
)
