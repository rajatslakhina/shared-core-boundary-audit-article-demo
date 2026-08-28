// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shared-core-boundary-audit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BoundaryAudit", targets: ["BoundaryAudit"]),
        .library(name: "BoundaryAuditUI", targets: ["BoundaryAuditUI"]),
    ],
    targets: [
        // Pure Swift. No Foundation, no platform imports — this target is the
        // thing the article is actually about, so it has to survive the test it
        // describes: it must compile on a machine that has never heard of UIKit.
        .target(name: "BoundaryAudit"),

        // The presentation layer. Guarded by `#if canImport(SwiftUI)` so the
        // package still builds on Linux, where this module compiles to nothing.
        .target(name: "BoundaryAuditUI", dependencies: ["BoundaryAudit"]),

        .testTarget(name: "BoundaryAuditTests", dependencies: ["BoundaryAudit"]),
    ]
)
