// swift-tools-version:5.9
import PackageDescription

// LiftCore is pure Foundation so the iPhone app (phase 1) and the Watch app
// (phase 2) share one set of models, units, PR and progression rules.
let package = Package(
    name: "LiftKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "LiftCore", targets: ["LiftCore"]),
    ],
    targets: [
        .target(name: "LiftCore", resources: [.copy("Resources/exercise-library.json")]),
        .testTarget(name: "LiftCoreTests", dependencies: ["LiftCore"]),
    ]
)
