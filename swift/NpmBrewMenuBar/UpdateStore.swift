import Foundation

enum RefreshIntervalOption: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case twentyMinutes = 20
    case thirtyMinutes = 30

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .oneMinute:
            return L.text("1 min", "1 min")
        case .fiveMinutes:
            return L.text("5 min", "5 min")
        case .tenMinutes:
            return L.text("10 min", "10 min")
        case .twentyMinutes:
            return L.text("20 min", "20 min")
        case .thirtyMinutes:
            return L.text("30 min", "30 min")
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

@MainActor
final class UpdateStore: ObservableObject {
    private enum DefaultsKey {
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
    }

    private enum UpdateFlowError: LocalizedError {
        case requiresManualHomebrewCask(package: String)

        var errorDescription: String? {
            switch self {
            case .requiresManualHomebrewCask(let package):
                return L.text(
                    "Le cask Homebrew \(package) requiert une authentification administrateur que l'app ne peut pas afficher inline. Mets-le a jour manuellement.",
                    "The Homebrew cask \(package) requires administrator authentication that the app cannot show inline. Update it manually."
                )
            }
        }
    }

    @Published private(set) var updates: [PackageUpdate] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isUpdating = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var logs: [String] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var npmStatusMessage: String?
    @Published var selectedRefreshInterval: RefreshIntervalOption {
        didSet {
            UserDefaults.standard.set(selectedRefreshInterval.rawValue, forKey: DefaultsKey.refreshIntervalMinutes)
            log(L.text(
                "Refresh automatique regle sur \(selectedRefreshInterval.label).",
                "Auto-refresh set to \(selectedRefreshInterval.label)."
            ))
            restartAutoRefreshLoop()
        }
    }

    private var autoRefreshTask: Task<Void, Never>?

    init() {
        let storedValue = UserDefaults.standard.integer(forKey: DefaultsKey.refreshIntervalMinutes)
        selectedRefreshInterval = RefreshIntervalOption(rawValue: storedValue) ?? .fiveMinutes
        startAutoRefreshLoop()
        Task { @MainActor in
            refresh()
        }
    }

    var totalUpdates: Int { updates.count }

    var statusText: String {
        if isRefreshing {
            return L.text("Analyse des mises a jour...", "Checking for updates...")
        }
        if isUpdating {
            return L.text("Mise a jour en cours...", "Update in progress...")
        }
        if totalUpdates == 0 {
            return L.text("Tout est a jour", "Everything is up to date")
        }
        return L.text(
            "\(totalUpdates) mise(s) a jour disponible(s)",
            "\(totalUpdates) update(s) available"
        )
    }

    var statusIcon: String {
        if isRefreshing || isUpdating {
            return "arrow.triangle.2.circlepath"
        }
        return totalUpdates == 0 ? "checkmark.circle.fill" : "arrow.down.circle.fill"
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        npmStatusMessage = nil
        log(L.text("Debut de l'analyse des paquets.", "Starting package scan."))

        Task {
            defer { isRefreshing = false }

            do {
                async let brew = fetchHomebrewUpdates()
                async let npm = fetchNpmUpdates()
                let combined = try await brew + npm
                updates = combined.sorted {
                    if $0.source == $1.source { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    return $0.source.rawValue < $1.source.rawValue
                }
                lastRefresh = Date()
                log(L.text(
                    "Analyse terminee: \(combined.count) mise(s) a jour detectee(s).",
                    "Scan completed: \(combined.count) update(s) found."
                ))
            } catch {
                errorMessage = error.localizedDescription
                log(L.text(
                    "Erreur pendant l'analyse: \(error.localizedDescription)",
                    "Error while scanning: \(error.localizedDescription)"
                ))
            }
        }
    }

    func updateAll() {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        log(L.text("Demarrage de la mise a jour complete.", "Starting full update."))

        Task {
            defer { isUpdating = false }

            do {
                try await updateHomebrewIfAvailable()
                try await updateNpmGlobalsIfAvailable()
                log(L.text("Mises a jour terminees.", "Updates completed."))
                refresh()
            } catch {
                errorMessage = error.localizedDescription
                log(L.text(
                    "Erreur pendant la mise a jour: \(error.localizedDescription)",
                    "Error while updating: \(error.localizedDescription)"
                ))
            }
        }
    }

    func update(_ package: PackageUpdate) {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        log(L.text(
            "Mise a jour ciblee de \(package.name).",
            "Updating \(package.name)."
        ))

        Task {
            defer { isUpdating = false }

            do {
                switch package.source {
                case .homebrew:
                    try await updateHomebrewPackage(package)
                case .npm:
                    _ = try await run("/bin/zsh", arguments: ["-lc", "npm install -g \(shellEscape(package.name))@latest"])
                }
                log(L.text(
                    "Mise a jour de \(package.name) terminee.",
                    "\(package.name) update completed."
                ))
                refresh()
            } catch {
                errorMessage = error.localizedDescription
                log(L.text(
                    "Erreur pendant la mise a jour de \(package.name): \(error.localizedDescription)",
                    "Error while updating \(package.name): \(error.localizedDescription)"
                ))
            }
        }
    }

    private func fetchHomebrewUpdates() async throws -> [PackageUpdate] {
        guard Shell.which("brew") else {
            log(L.text("Homebrew non installe, verification ignoree.", "Homebrew not installed, skipping check."))
            return []
        }

        let output = try await run("/bin/zsh", arguments: ["-lc", "brew outdated --json=v2"])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log(L.text(
                "Homebrew: aucune donnee retournee, considere comme aucune mise a jour.",
                "Homebrew: no data returned, treating as no updates."
            ))
            return []
        }

        let data = Data(trimmed.utf8)
        let decoded = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data)

        let formulas = decoded.formulae.map {
            PackageUpdate(
                name: $0.name,
                currentVersion: $0.installedVersions.last ?? L.text("inconnue", "unknown"),
                latestVersion: $0.currentVersion,
                source: .homebrew,
                kind: "formula"
            )
        }

        let casks = decoded.casks.map {
            PackageUpdate(
                name: $0.name,
                currentVersion: $0.installedVersions.last ?? L.text("inconnue", "unknown"),
                latestVersion: $0.currentVersion,
                source: .homebrew,
                kind: "cask"
            )
        }

        return formulas + casks
    }

    private func fetchNpmUpdates() async throws -> [PackageUpdate] {
        guard Shell.which("npm") else {
            npmStatusMessage = L.text("npm n'est pas installe.", "npm is not installed.")
            log(L.text("npm non installe, verification ignoree.", "npm not installed, skipping check."))
            return []
        }

        let command = "npm outdated -g --depth=0 --json"
        let output: String

        do {
            output = try await run("/bin/zsh", arguments: ["-lc", "\(command) 2>/dev/null || true"])
        } catch {
            npmStatusMessage = L.text("Aucun paquet npm a mettre a jour.", "No npm packages to update.")
            log(L.text("npm: erreur ignoree pendant la verification.", "npm: ignoring check error."))
            return []
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await fetchNpmUpdatesFromTableFallback()
        }
        guard trimmed.first == "{" else {
            return try await fetchNpmUpdatesFromTableFallback()
        }

        let data = Data(trimmed.utf8)
        let decoded: [String: NpmOutdatedEntry]

        do {
            decoded = try JSONDecoder().decode([String: NpmOutdatedEntry].self, from: data)
        } catch {
            return try await fetchNpmUpdatesFromTableFallback()
        }

        if decoded.isEmpty {
            npmStatusMessage = L.text("Aucun paquet npm a mettre a jour.", "No npm packages to update.")
        } else {
            npmStatusMessage = L.text(
                "\(decoded.count) mise(s) a jour npm detectee(s).",
                "\(decoded.count) npm update(s) detected."
            )
        }

        return decoded
            .map { name, entry in
                PackageUpdate(
                    name: name,
                    currentVersion: entry.current,
                    latestVersion: entry.latest,
                    source: .npm,
                    kind: "global"
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fetchNpmUpdatesFromTableFallback() async throws -> [PackageUpdate] {
        let output = try await run("/bin/zsh", arguments: ["-lc", "npm outdated -g || true"])
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else {
            npmStatusMessage = L.text("Aucun paquet npm a mettre a jour.", "No npm packages to update.")
            return []
        }

        let dataLines = lines.dropFirst()
        let updates = dataLines.compactMap(parseNpmOutdatedTableLine)

        if updates.isEmpty {
            npmStatusMessage = L.text("Aucun paquet npm a mettre a jour.", "No npm packages to update.")
        } else {
            npmStatusMessage = L.text(
                "\(updates.count) mise(s) a jour npm detectee(s).",
                "\(updates.count) npm update(s) detected."
            )
        }

        return updates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseNpmOutdatedTableLine(_ line: String) -> PackageUpdate? {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 4 else { return nil }

        let name = parts[0]
        let current = parts[1] == "MISSING" ? L.text("non installe", "not installed") : parts[1]
        let wanted = parts[2]
        let latest = parts[3]
        let targetVersion = latest.isEmpty ? wanted : latest

        return PackageUpdate(
            name: name,
            currentVersion: current,
            latestVersion: targetVersion,
            source: .npm,
            kind: "global"
        )
    }

    private func updateHomebrewIfAvailable() async throws {
        guard Shell.which("brew") else {
            log(L.text("Homebrew absent, mise a jour ignoree.", "Homebrew missing, skipping update."))
            return
        }

        log("Homebrew: brew update")
        _ = try await run("/bin/zsh", arguments: ["-lc", "brew update"])

        let packages = try await fetchHomebrewUpdates()
            .filter { $0.source == .homebrew }

        if packages.isEmpty {
            log(L.text("Homebrew: aucun paquet a mettre a jour", "Homebrew: no packages to update"))
        } else {
            var manualPackages: [String] = []

            for package in packages {
                do {
                    try await updateHomebrewPackage(package)
                } catch let error as UpdateFlowError {
                    switch error {
                    case .requiresManualHomebrewCask(let package):
                        manualPackages.append(package)
                        log(L.text(
                            "Homebrew: \(package) necessite une mise a jour manuelle",
                            "Homebrew: \(package) requires a manual update"
                        ))
                    }
                }
            }

            if !manualPackages.isEmpty {
                errorMessage = L.text(
                    "Mise a jour manuelle requise pour: \(manualPackages.joined(separator: ", ")).",
                    "Manual update required for: \(manualPackages.joined(separator: ", "))."
                )
            }
        }

        log("Homebrew: brew cleanup")
        _ = try await run("/bin/zsh", arguments: ["-lc", "brew cleanup"])
    }

    private func updateNpmGlobalsIfAvailable() async throws {
        guard Shell.which("npm") else {
            log(L.text("npm absent, mise a jour ignoree.", "npm missing, skipping update."))
            return
        }

        let rootOutput = try await run("/bin/zsh", arguments: ["-lc", "npm root -g"])
        let npmRoot = rootOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        if !npmRoot.isEmpty {
            log(L.text("npm: nettoyage des dossiers temporaires", "npm: cleaning temporary folders"))
            _ = try await run(
                "/bin/zsh",
                arguments: ["-lc", "find \(shellEscape(npmRoot)) -maxdepth 1 -mindepth 1 -type d \\( -name '.*-*' -o -name '.npm-*' \\) -exec rm -rf {} + 2>/dev/null || true"]
            )
        }

        let listOutput = try await run("/bin/zsh", arguments: ["-lc", "npm ls -g --depth=0 --parseable 2>/dev/null || true"])
        let packages = parseGlobalPackages(listOutput: listOutput, npmRoot: npmRoot)

        guard !packages.isEmpty else {
            log(L.text("npm: aucun paquet global detecte", "npm: no global packages detected"))
            return
        }

        for package in packages {
            log(L.text("npm: mise a jour de \(package)", "npm: updating \(package)"))
            _ = try await run("/bin/zsh", arguments: ["-lc", "npm install -g \(shellEscape(package))@latest"])
        }
    }

    private func parseGlobalPackages(listOutput: String, npmRoot: String) -> [String] {
        let lines = listOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        let parent = URL(fileURLWithPath: npmRoot).deletingLastPathComponent().path

        return lines.compactMap { line in
            guard line != parent, line != npmRoot else { return nil }
            guard line.hasPrefix(npmRoot + "/") else { return nil }
            let relative = String(line.dropFirst(npmRoot.count + 1))
            return relative.isEmpty ? nil : relative
        }
    }

    private func updateHomebrewPackage(_ package: PackageUpdate) async throws {
        let isCask = package.kind == "cask"
        let command = isCask
            ? "brew upgrade --cask \(shellEscape(package.name))"
            : "brew upgrade \(shellEscape(package.name))"

        log("Homebrew: mise a jour de \(package.name)")

        do {
            _ = try await run("/bin/zsh", arguments: ["-lc", command])
        } catch {
            guard isCask, requiresAdministratorPrivileges(error) else {
                throw error
            }

            throw UpdateFlowError.requiresManualHomebrewCask(package: package.name)
        }
    }

    private func run(_ launchPath: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Shell.run(launchPath, arguments: arguments).stdout
        }.value
    }

    private func requiresAdministratorPrivileges(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("sudo: a terminal is required")
            || message.contains("sudo: a password is required")
            || message.contains("askpass")
    }

    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        let interval = selectedRefreshInterval.seconds

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    private func restartAutoRefreshLoop() {
        startAutoRefreshLoop()
    }

    private func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        logs.insert("[\(formatter.string(from: Date()))] \(message)", at: 0)
        if logs.count > 200 {
            logs = Array(logs.prefix(200))
        }
    }
}

private struct BrewOutdatedResponse: Decodable {
    let formulae: [BrewFormula]
    let casks: [BrewCask]
}

private struct BrewFormula: Decodable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}

private struct BrewCask: Decodable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}

private struct NpmOutdatedEntry: Decodable {
    let current: String
    let latest: String
}
