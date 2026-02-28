// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScribeFlowPro",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "0.1.12"),
    ],
    targets: [
        .executableTarget(
            name: "ScribeFlowPro",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            path: "ScribeFlowPro"
        ),
        .testTarget(
            name: "ScribeFlowProTests",
            dependencies: ["ScribeFlowPro"],
            path: "Tests"
        ),
    ]
)
