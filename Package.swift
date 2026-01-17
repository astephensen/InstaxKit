// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "InstaxKit",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    .library(
      name: "InstaxKit",
      targets: ["InstaxKit"]
    ),
    .executable(
      name: "instax",
      targets: ["InstaxCLI"]
    ),
    .executable(
      name: "instax-mock-server",
      targets: ["InstaxMockServer"]
    ),
    .executable(
      name: "InstaxKitServer",
      targets: ["InstaxKitServer"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "InstaxKit",
      dependencies: []
    ),
    .executableTarget(
      name: "InstaxCLI",
      dependencies: [
        "InstaxKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .executableTarget(
      name: "InstaxMockServer",
      dependencies: [
        "InstaxKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .executableTarget(
      name: "InstaxKitServer",
      dependencies: ["InstaxKit"]
    ),
    .testTarget(
      name: "InstaxKitTests",
      dependencies: ["InstaxKit"],
      resources: [
        .copy("Resources"),
      ]
    ),
  ]
)
