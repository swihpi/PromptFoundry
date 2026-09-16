// swift-tools-version: 6.0
import PackageDescription
import Foundation

let bundledSwiftDataPlugin = "/Applications/Swift Playground.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/libSwiftDataMacros.dylib"
let swiftDataPluginPath = ProcessInfo.processInfo.environment["PROMPTFOUNDRY_SWIFTDATA_PLUGIN"] ?? bundledSwiftDataPlugin
let swiftDataSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: swiftDataPluginPath)
    ? [.unsafeFlags([
        "-Xfrontend", "-load-plugin-library",
        "-Xfrontend", swiftDataPluginPath
    ])]
    : []

let package = Package(
    name: "PromptFoundry",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PromptFoundryCore", targets: ["PromptFoundryCore"]),
        .executable(name: "PromptFoundry", targets: ["PromptFoundry"]),
        .executable(name: "PromptFoundryVerification", targets: ["PromptFoundryVerification"]),
        .executable(name: "PromptFoundryCodexProbe", targets: ["PromptFoundryCodexProbe"])
    ],
    targets: [
        .target(
            name: "PromptFoundryCore",
            swiftSettings: swiftDataSettings,
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "PromptFoundry",
            dependencies: ["PromptFoundryCore"],
            path: "Sources/PromptFoundryApp",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "PromptFoundryVerification",
            dependencies: ["PromptFoundryCore"],
            path: "Verification"
        ),
        .executableTarget(
            name: "PromptFoundryCodexProbe",
            dependencies: ["PromptFoundryCore"],
            path: "IntegrationProbe"
        )
    ],
    swiftLanguageModes: [.v5]
)
