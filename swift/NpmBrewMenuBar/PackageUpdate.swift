import Foundation

enum PackageSource: String, CaseIterable, Codable, Sendable {
    case homebrew = "Homebrew"
    case npm = "npm"
}

struct PackageUpdate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let currentVersion: String
    let latestVersion: String
    let source: PackageSource
    let kind: String

    init(
        name: String,
        currentVersion: String,
        latestVersion: String,
        source: PackageSource,
        kind: String
    ) {
        self.id = "\(source.rawValue)::\(kind)::\(name)"
        self.name = name
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.source = source
        self.kind = kind
    }
}
