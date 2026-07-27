// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "native_datastore",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "native-datastore", targets: ["native_datastore"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "native_datastore",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // The plugin reads and writes UserDefaults on iOS, which is a
                // required-reason API. PrivacyInfo.xcprivacy declares that use.
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
