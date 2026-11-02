// swift-tools-version:5.9
// EH3D-IOS-CONTROL - the rules of the iPhone app (server link, models, geometry, languages) in a package with no UIKit or SwiftUI, so they are tested without a phone.
import PackageDescription

let package = Package(
    name: "Eh3dCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "Eh3dCore", targets: ["Eh3dCore"])],
    targets: [
        .target(name: "Eh3dCore", resources: [.copy("Resources/i18n")]),
        .testTarget(name: "Eh3dCoreTests", dependencies: ["Eh3dCore"]),
    ]
)
