// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EasyTierNativeMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "EasyTierCore", targets: ["EasyTierCore"]),
        .executable(name: "EasyTierMac", targets: ["EasyTierMac"]),
        .executable(name: "EasyTierValidator", targets: ["EasyTierValidator"]),
        .executable(name: "EasyTierPrivilegedHelper", targets: ["EasyTierPrivilegedHelper"]),
    ],
    targets: [
        .target(
            name: "CEasyTierFFI",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-LVendor/Frameworks/static", "-leasytier_ffi"]),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .target(
            name: "EasyTierCore",
            dependencies: ["CEasyTierFFI"],
            linkerSettings: [
                .linkedLibrary("System"),
            ]
        ),
        .executableTarget(
            name: "EasyTierMac",
            dependencies: ["EasyTierCore"]
        ),
        .executableTarget(
            name: "EasyTierValidator",
            dependencies: ["EasyTierCore"]
        ),
        .executableTarget(
            name: "EasyTierPrivilegedHelper",
            dependencies: ["EasyTierCore"]
        ),
        .testTarget(
            name: "EasyTierCoreTests",
            dependencies: ["EasyTierCore"]
        ),
    ]
)
