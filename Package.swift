// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BusymateAI",
    platforms: [.iOS(.v15)],
    products: [.library(name: "BusymateAI", targets: ["BusymateAI"])],
    targets: [.target(name: "BusymateAI")],
    swiftLanguageVersions: [.v5]
)
