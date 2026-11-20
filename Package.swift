// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EnchantCore", platforms: [.macOS(.v13), .iOS(.v17), .watchOS(.v10)], products: [.library(name: "EnchantCore", targets: ["EnchantCore"])], targets: [.target(name: "EnchantCore"), .testTarget(name: "EnchantCoreTests", dependencies: ["EnchantCore"])])
