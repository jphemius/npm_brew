import Foundation
import AppKit
import UserNotifications

enum AppReleaseCheckInterval: Int, CaseIterable, Identifiable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case sixtyMinutes = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fiveMinutes:
            return "5 min"
        case .fifteenMinutes:
            return "15 min"
        case .thirtyMinutes:
            return "30 min"
        case .sixtyMinutes:
            return "60 min"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

struct AppReleaseInfo: Sendable {
    let version: String
    let url: URL
    let publishedAt: Date?
    let assetDownloadURL: URL?
    let assetName: String?
}

@MainActor
final class AppUpdateManager: ObservableObject {
    private enum DefaultsKey {
        static let appReleaseCheckInterval = "appReleaseCheckInterval"
    }

    @Published private(set) var latestRelease: AppReleaseInfo?
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published var selectedCheckInterval: AppReleaseCheckInterval {
        didSet {
            UserDefaults.standard.set(selectedCheckInterval.rawValue, forKey: DefaultsKey.appReleaseCheckInterval)
            startAutoCheckLoop()
        }
    }

    private let owner = "jphemius"
    private let repo = "npm_brew"
    private var didNotifyAvailableUpdate = false
    private var autoCheckTask: Task<Void, Never>?

    init() {
        let storedValue = UserDefaults.standard.integer(forKey: DefaultsKey.appReleaseCheckInterval)
        selectedCheckInterval = AppReleaseCheckInterval(rawValue: storedValue) ?? .fifteenMinutes
        startAutoCheckLoop()
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var updateAvailable: Bool {
        guard let latestRelease else { return false }
        return isVersion(latestRelease.version, newerThan: currentVersion)
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil

        Task {
            defer { isChecking = false }

            do {
                let release = try await fetchLatestRelease()
                latestRelease = release
                lastCheckedAt = Date()
                if updateAvailable {
                    statusMessage = L.text(
                        "Nouvelle version \(release.version) detectee.",
                        "New version \(release.version) detected."
                    )
                    notifyIfNeeded(for: release)
                } else {
                    statusMessage = nil
                    didNotifyAvailableUpdate = false
                }
            } catch {
                lastCheckedAt = Date()
                errorMessage = error.localizedDescription
            }
        }
    }

    func openLatestRelease() {
        guard let url = latestRelease?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func downloadAndInstallUpdate() {
        guard !isDownloading else { return }
        guard let latestRelease, updateAvailable else { return }
        guard let assetURL = latestRelease.assetDownloadURL else {
            errorMessage = L.text(
                "Aucun asset .zip d'application n'a ete trouve dans la derniere release GitHub.",
                "No app .zip asset was found in the latest GitHub release."
            )
            return
        }

        isDownloading = true
        errorMessage = nil
        statusMessage = L.text(
            "Telechargement de la mise a jour...",
            "Downloading update..."
        )

        Task {
            defer { isDownloading = false }

            do {
                try await downloadAndInstall(release: latestRelease, assetURL: assetURL)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
        }
    }

    private func fetchLatestRelease() async throws -> AppReleaseInfo {
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NpmBrewMenuBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw AppUpdateError.noReleasePublished
            }
            throw AppUpdateError.httpStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder.github.decode(GitHubLatestReleaseResponse.self, from: data)
        let version = normalizedVersion(decoded.tagName)
        let asset = preferredAsset(from: decoded.assets)

        guard let url = URL(string: decoded.htmlURL) else {
            throw AppUpdateError.invalidResponse
        }

        return AppReleaseInfo(
            version: version,
            url: url,
            publishedAt: decoded.publishedAt,
            assetDownloadURL: asset.flatMap { URL(string: $0.browserDownloadURL) },
            assetName: asset?.name
        )
    }

    private func preferredAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        let zipAssets = assets.filter { $0.name.lowercased().hasSuffix(".zip") }

        if let preferred = zipAssets.first(where: { asset in
            let name = asset.name.lowercased()
            return !name.contains("source code")
                && !name.contains("source")
                && (name.contains("mac") || name.contains("app") || name.contains("npmbrew"))
        }) {
            return preferred
        }

        return zipAssets.first(where: { !$0.name.lowercased().contains("source code") }) ?? zipAssets.first
    }

    private func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }

        return false
    }

    private func notifyIfNeeded(for release: AppReleaseInfo) {
        guard !didNotifyAvailableUpdate else { return }
        didNotifyAvailableUpdate = true

        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = L.text("Nouvelle version disponible", "New version available")
            content.body = L.text(
                "NPM Brew \(release.version) est disponible.",
                "NPM Brew \(release.version) is available."
            )
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "app-update-\(release.version)",
                content: content,
                trigger: nil
            )

            try? await center.add(request)
        }
    }

    private func startAutoCheckLoop() {
        autoCheckTask?.cancel()
        let interval = selectedCheckInterval.seconds

        autoCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                await self?.checkForUpdates()
            }
        }
    }

    private func downloadAndInstall(release: AppReleaseInfo, assetURL: URL) async throws {
        let installURL = Bundle.main.bundleURL.standardizedFileURL
        guard installURL.pathExtension == "app" else {
            throw AppUpdateError.notInstalledAsApp
        }

        let installDirectory = installURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: installDirectory.path) else {
            throw AppUpdateError.installLocationNotWritable(installDirectory.path)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("npm-brew-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let archiveURL = tempRoot.appendingPathComponent(release.assetName ?? "NpmBrewMenuBar.zip")
        let extractedURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedURL, withIntermediateDirectories: true)

        statusMessage = L.text("Telechargement termine, preparation de l'installation...", "Download complete, preparing installation...")

        let (downloadedFileURL, response) = try await URLSession.shared.download(from: assetURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AppUpdateError.downloadFailed
        }

        try? FileManager.default.removeItem(at: archiveURL)
        try FileManager.default.moveItem(at: downloadedFileURL, to: archiveURL)

        try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractedURL.path])

        guard let newAppURL = findAppBundle(in: extractedURL) else {
            throw AppUpdateError.appBundleMissing
        }

        statusMessage = L.text("Installation de la mise a jour...", "Installing update...")
        try launchReplacementScript(newAppURL: newAppURL, currentAppURL: installURL)

        statusMessage = L.text("Relance de l'application...", "Restarting app...")
        NSApp.terminate(nil)
    }

    private func findAppBundle(in directory: URL) -> URL? {
        if directory.pathExtension == "app" {
            return directory
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                return url
            }
        }

        return nil
    }

    private func runProcess(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AppUpdateError.processFailed(stderr.isEmpty ? launchPath : stderr)
        }
    }

    private func launchReplacementScript(newAppURL: URL, currentAppURL: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("npm-brew-replace-\(UUID().uuidString).sh")

        let script = """
        #!/bin/sh
        set -e
        sleep 2
        rm -rf "\(currentAppURL.path)"
        cp -R "\(newAppURL.path)" "\(currentAppURL.path)"
        open "\(currentAppURL.path)"
        rm -f "$0"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]

        try process.run()
    }
}

private enum AppUpdateError: LocalizedError {
    case invalidResponse
    case noReleasePublished
    case httpStatus(Int)
    case notInstalledAsApp
    case installLocationNotWritable(String)
    case downloadFailed
    case appBundleMissing
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return L.text(
                "Reponse invalide pendant la verification de la nouvelle version.",
                "Invalid response while checking the app update."
            )
        case .noReleasePublished:
            return L.text(
                "Aucune release GitHub n'est publiee pour l'application.",
                "No GitHub release has been published for the app."
            )
        case .httpStatus(let code):
            return L.text(
                "La verification de version a echoue avec le code HTTP \(code).",
                "Version check failed with HTTP status \(code)."
            )
        case .notInstalledAsApp:
            return L.text(
                "L'application courante n'est pas executee depuis un bundle .app installable.",
                "The current app is not running from an installable .app bundle."
            )
        case .installLocationNotWritable(let path):
            return L.text(
                "Le dossier d'installation n'est pas inscriptible: \(path). Installe plutot l'app dans ~/Applications ou mets-la a jour manuellement.",
                "The install directory is not writable: \(path). Install the app in ~/Applications or update it manually."
            )
        case .downloadFailed:
            return L.text(
                "Le telechargement de l'asset de release a echoue.",
                "Downloading the release asset failed."
            )
        case .appBundleMissing:
            return L.text(
                "Le fichier telecharge ne contient pas de bundle .app exploitable.",
                "The downloaded file does not contain a usable .app bundle."
            )
        case .processFailed(let details):
            return L.text(
                "L'installation automatique a echoue: \(details)",
                "Automatic installation failed: \(details)"
            )
        }
    }
}

private struct GitHubLatestReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: String
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
