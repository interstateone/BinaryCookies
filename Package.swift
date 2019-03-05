// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "BinaryCookies",
    products: [
        .library(name: "BinaryCookies", targets: ["BinaryCookies"]),
        .executable(name: "dumpcookies", targets: ["dumpcookies"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jverkoey/BinaryCodable", .revision("2d4834e4972c46bdb3ec59d025ba29b7e9b7522b")),
    ],
    targets: [
        .target(name: "BinaryCookies", dependencies: ["BinaryCodable"]),
        .target(name: "dumpcookies", dependencies: ["BinaryCookies"]),
    ]
)
