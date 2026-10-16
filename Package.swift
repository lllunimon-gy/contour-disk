// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Contour",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "Contour", targets: ["Contour", "ContourObjC"])],
    targets: [

        .target(name: "ContourObjC", publicHeadersPath: "include"),
        .target(name: "Contour", dependencies: ["ContourObjC"]),

        .testTarget(name: "ContourTests", dependencies: ["Contour"])
    ]
)
