// swift-tools-version:5.8
import PackageDescription

let package = Package(
  name: "backend",
  platforms: [
    .macOS("13.3"),
  ],
  products: [
    .executable(name: "backend", targets: ["App"]),
  ],
  dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.77.1"),
    .package(path: "../packages/Foundations"),
    .package(path: "../third_party/Jobs"),
    .package(path: "../third_party/GoogleCloudLogging"),
    .package(url: "https://github.com/vapor/apns.git", from: "4.0.0")
  ],
  targets: [
    .executableTarget(
      name: "App",
      dependencies: [
        .product(name: "VaporAPNS", package: "apns"),
        .product(name: "Vapor", package: "vapor"),
        .product(name: "Jobs", package: "Jobs"),
        .product(name: "GoogleCloudLogging", package: "GoogleCloudLogging"),
        .product(name: "Activities", package: "Foundations"),
        .product(name: "BackendAPI", package: "Foundations"),
        .product(name: "GarageModel", package: "Foundations"),
        .product(name: "NetworkClient", package: "Foundations"),
        .product(name: "PorscheAPI", package: "Foundations"),
        .product(name: "PorscheDataModel", package: "Foundations"),
        .product(name: "PorscheDataModelTranslator", package: "Foundations"),
      ],
      resources: [
        .copy("DevAuthKey.p8"),
        .copy("backend-logger.json"),
        .copy("serverconfig.json"),
      ]
    ),
    .testTarget(name: "AppTests", dependencies: [
      .target(name: "App"),
      .product(name: "XCTVapor", package: "vapor"),
    ])
  ]
)

