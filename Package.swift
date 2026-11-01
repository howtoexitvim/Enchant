// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Enchant",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "Enchant", targets: ["Enchant"])
    ],
    targets: [
        .target(name: "Enchant")
    ]
)
