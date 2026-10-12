// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Llamastat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Llamastat",
            path: "Sources/Llamastat"
        )
    ]
)
