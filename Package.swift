// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "TotersLokalise",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(name: "TotersLokalise", targets: ["TotersLokalise"])
  ],
  targets: [
    .target(name: "TotersLokalise"),
    .testTarget(
      name: "TotersLokaliseTests",
      dependencies: ["TotersLokalise"],
      resources: [
        .copy("Fixtures/golden.json")
      ]
    ),
  ]
)
