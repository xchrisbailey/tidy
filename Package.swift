// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Tidy",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TidyCore", targets: ["TidyCore"]),
    .executable(name: "Tidy", targets: ["TidyApp"]),
  ],
  targets: [
    .target(name: "TidyCore"),
    .executableTarget(name: "TidyApp", dependencies: ["TidyCore"]),
    .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore"]),
  ]
)
