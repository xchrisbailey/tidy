// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Tidy",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TidyCore", targets: ["TidyCore"]),
    .library(name: "TidyModel", targets: ["TidyModel"]),
    .library(name: "TidyModelRuntime", targets: ["TidyModelRuntime"]),
    .executable(name: "Tidy", targets: ["TidyApp"]),
    .executable(name: "TidyModelSmoke", targets: ["TidyModelSmoke"]),
    .executable(name: "TidyInspectionHelper", targets: ["TidyInspectionHelper"]),
  ],
  dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
    .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.32.3"),
    .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5"),
  ],
  targets: [
    .target(name: "TidyCore"),
    .executableTarget(name: "TidyInspectionHelper"),
    .target(name: "TidyModel"),
    .target(
      name: "TidyModelRuntime",
      dependencies: [
        "TidyModel",
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ]),
    .executableTarget(
      name: "TidyApp", dependencies: ["TidyCore", "TidyModel", "TidyModelRuntime"]),
    .executableTarget(
      name: "TidyModelSmoke",
      dependencies: [
        "TidyCore", "TidyModel", "TidyModelRuntime",
        .product(name: "MLX", package: "mlx-swift"),
      ]),
    .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore"]),
    .testTarget(name: "TidyModelTests", dependencies: ["TidyModel"]),
  ]
)
