// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "BinaryCookies",
    products: [
        .library(name: "BinaryCookies", targets: ["BinaryCookies"]),
        .executable(name: "dumpcookies", targets: ["dumpcookies"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jverkoey/BinaryCodable", .upToNextMinor(from: "0.2.0")),
    ],
    targets: [
        .target(name: "BinaryCookies", dependencies: ["BinaryCodable"]),
        .target(name: "dumpcookies", dependencies: ["BinaryCookies"]),
    ]
)
