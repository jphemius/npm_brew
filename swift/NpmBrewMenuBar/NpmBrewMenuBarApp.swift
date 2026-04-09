import SwiftUI
import AppKit

@main
struct NpmBrewMenuBarApp: App {
    @StateObject private var store = UpdateStore()
    @StateObject private var loginItemManager = LoginItemManager()
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var appUpdateManager = AppUpdateManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .environmentObject(loginItemManager)
                .environmentObject(languageManager)
                .environmentObject(appUpdateManager)
                .frame(width: 380, height: 520)
        } label: {
            Label(store.totalUpdates == 0 ? languageManager.text("A jour", "Up to date") : "\(store.totalUpdates)", systemImage: store.statusIcon)
        }
        .menuBarExtraStyle(.window)

        Window(languageManager.text("Paquets a mettre a jour", "Packages to update"), id: "updates-window") {
            UpdatesDashboardView()
                .environmentObject(store)
                .environmentObject(loginItemManager)
                .environmentObject(languageManager)
                .environmentObject(appUpdateManager)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var store: UpdateStore
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @EnvironmentObject private var languageManager: LanguageManager
    @EnvironmentObject private var appUpdateManager: AppUpdateManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    quickActions
                    Divider()
                    packagePreview
                    Divider()
                    refreshSection
                    Divider()
                    loginSection
                    appUpdateBanner
                    if let updateStatusMessage = appUpdateManager.statusMessage {
                        Text(updateStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let npmStatusMessage = store.npmStatusMessage {
                        Text(npmStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .padding(.bottom, 12)
            }

            Divider()

            HStack {
                Spacer()
                Button(languageManager.text("Quitter", "Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .task {
            if store.lastRefresh == nil {
                store.refresh()
            }
            if appUpdateManager.latestRelease == nil {
                appUpdateManager.checkForUpdates()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Npm Brew")
                .font(.title2.weight(.semibold))
            Text(store.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let lastRefresh = store.lastRefresh {
                Text(languageManager.text("Derniere verification", "Last check") + ": \(lastRefresh.formatted(date: .numeric, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                store.refresh()
            } label: {
                Label(languageManager.text("Rafraichir", "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing || store.isUpdating)

            Button {
                store.updateAll()
            } label: {
                Label(languageManager.text("Tout mettre a jour", "Update all"), systemImage: "square.and.arrow.down")
            }
            .disabled(store.isRefreshing || store.isUpdating || store.updates.isEmpty)

            Button {
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "updates-window")
                }
            } label: {
                Label(languageManager.text("Ouvrir le detail", "Open details"), systemImage: "list.bullet.rectangle.portrait")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var packagePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(languageManager.text("Apercu", "Preview"))
                .font(.headline)

            if store.updates.isEmpty {
                Label(languageManager.text("Aucune mise a jour detectee", "No updates detected"), systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.updates.prefix(5)) { package in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(package.name)
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(package.source.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(package.currentVersion) -> \(package.latestVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var loginSection: some View {
        Toggle(isOn: Binding(
            get: { loginItemManager.isEnabled },
            set: { loginItemManager.setEnabled($0) }
        )) {
            Text(languageManager.text("Lancer au demarrage du Mac", "Launch when logging into macOS"))
        }
        .toggleStyle(.switch)
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.text("Refresh auto", "Auto refresh"))
                .font(.headline)

            Picker(languageManager.text("Refresh auto", "Auto refresh"), selection: $store.selectedRefreshInterval) {
                ForEach(RefreshIntervalOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(languageManager.text(
                "Verification automatique toutes les \(store.selectedRefreshInterval.label.lowercased()).",
                "Automatic check every \(store.selectedRefreshInterval.label.lowercased())."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(languageManager.text("Langue", "Language"), selection: $languageManager.currentLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var appUpdateBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.text("Mise a jour de l'app", "App update"))
                .font(.headline)

            Text(languageManager.text(
                "Version actuelle \(appUpdateManager.currentVersion)",
                "Current version \(appUpdateManager.currentVersion)"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if let latestRelease = appUpdateManager.latestRelease {
                Text(languageManager.text(
                    "Derniere release GitHub \(latestRelease.version).",
                    "Latest GitHub release \(latestRelease.version)."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(languageManager.text(
                    "Aucune release GitHub detectee pour le moment.",
                    "No GitHub release detected yet."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let lastCheckedAt = appUpdateManager.lastCheckedAt {
                Text(languageManager.text("Dernier check release", "Last release check") + ": \(lastCheckedAt.formatted(date: .numeric, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(appUpdateManager.updateAvailable
                ? languageManager.text("Une mise a jour est disponible.", "An update is available.")
                : languageManager.text("L'application est deja a jour.", "The app is already up to date.")
            )
            .font(.caption)
            .foregroundStyle(appUpdateManager.updateAvailable ? .orange : .secondary)

            HStack(spacing: 8) {
                Button {
                    appUpdateManager.checkForUpdates()
                } label: {
                    Label(languageManager.text("Verifier l'app", "Check app"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appUpdateManager.isChecking)

                Button {
                    appUpdateManager.openLatestRelease()
                } label: {
                    Label(languageManager.text("Ouvrir la release", "Open release"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appUpdateManager.latestRelease == nil)

                Button {
                    appUpdateManager.downloadAndInstallUpdate()
                } label: {
                    Label(
                        languageManager.text("Telecharger la mise a jour", "Download update"),
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!appUpdateManager.updateAvailable || appUpdateManager.isDownloading)
            }
        }
        .padding(12)
        .background((appUpdateManager.updateAvailable ? Color.orange : Color.secondary).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct UpdatesDashboardView: View {
    @EnvironmentObject private var store: UpdateStore
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @EnvironmentObject private var languageManager: LanguageManager
    @EnvironmentObject private var appUpdateManager: AppUpdateManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolbarSection
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.08))
                }
                if let npmStatusMessage = store.npmStatusMessage {
                    Text(npmStatusMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.08))
                }
                if let updateStatusMessage = appUpdateManager.statusMessage {
                    Text(updateStatusMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.08))
                }
                packageList
                Divider()
                logSection
                Divider()
                appUpdateSection
            }
            .navigationTitle(languageManager.text("Mises a jour", "Updates"))
        }
        .task {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if store.lastRefresh == nil {
                store.refresh()
            }
            if appUpdateManager.latestRelease == nil {
                appUpdateManager.checkForUpdates()
            }
        }
    }

    private var toolbarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.statusText)
                        .font(.title3.weight(.semibold))
                    Text(languageManager.text("Homebrew et npm globaux", "Homebrew and global npm"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(languageManager.text("Demarrage auto", "Launch at login"), isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { loginItemManager.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .fixedSize()
            }

            HStack(spacing: 12) {
                Button {
                    store.refresh()
                } label: {
                    Label(languageManager.text("Verifier maintenant", "Check now"), systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing || store.isUpdating)

                Button {
                    appUpdateManager.checkForUpdates()
                } label: {
                    Label(languageManager.text("Verifier l'app", "Check app"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appUpdateManager.isChecking)

                Button {
                    appUpdateManager.downloadAndInstallUpdate()
                } label: {
                    Label(languageManager.text("Download update", "Download update"), systemImage: "arrow.down.circle")
                }
                .disabled(!appUpdateManager.updateAvailable || appUpdateManager.isDownloading)

                Button {
                    store.updateAll()
                } label: {
                    Label(languageManager.text("Mettre tout a jour", "Update all"), systemImage: "square.and.arrow.down")
                }
                .disabled(store.isRefreshing || store.isUpdating || store.updates.isEmpty)

                if let lastRefresh = store.lastRefresh {
                    Text(languageManager.text("Derniere verification", "Last check") + ": \(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Text(languageManager.text("Refresh auto", "Auto refresh"))
                    .font(.subheadline.weight(.medium))

                Picker(languageManager.text("Refresh auto", "Auto refresh"), selection: $store.selectedRefreshInterval) {
                    ForEach(RefreshIntervalOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Text(languageManager.text("Langue", "Language"))
                    .font(.subheadline.weight(.medium))

                Picker(languageManager.text("Langue", "Language"), selection: $languageManager.currentLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Text(languageManager.text("Check release", "Check release"))
                    .font(.subheadline.weight(.medium))

                Picker(languageManager.text("Check release", "Check release"), selection: $appUpdateManager.selectedCheckInterval) {
                    ForEach(AppReleaseCheckInterval.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .background(.thinMaterial)
    }

    private var appUpdateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(languageManager.text("Mise a jour de l'application", "App update"))
                    .font(.headline)
                Spacer()
                Button {
                    appUpdateManager.downloadAndInstallUpdate()
                } label: {
                    Label(languageManager.text("Download update", "Download update"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appUpdateManager.updateAvailable || appUpdateManager.isDownloading)

                Button {
                    appUpdateManager.openLatestRelease()
                } label: {
                    Label(languageManager.text("Ouvrir", "Open"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .disabled(appUpdateManager.latestRelease == nil)
            }

            Text(languageManager.text(
                "Version actuelle \(appUpdateManager.currentVersion).",
                "Current version \(appUpdateManager.currentVersion)."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let latestRelease = appUpdateManager.latestRelease {
                Text(languageManager.text(
                    "Derniere release GitHub \(latestRelease.version).",
                    "Latest GitHub release \(latestRelease.version)."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(languageManager.text(
                    "Aucune release GitHub detectee pour le moment.",
                    "No GitHub release detected yet."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lastCheckedAt = appUpdateManager.lastCheckedAt {
                Text(languageManager.text(
                    "Dernier check release \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened)).",
                    "Last release check \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(appUpdateManager.updateAvailable
                ? languageManager.text("Une mise a jour est disponible via GitHub Releases.", "An update is available via GitHub Releases.")
                : languageManager.text("L'application est deja a jour.", "The app is already up to date.")
            )
            .font(.subheadline)
            .foregroundStyle(appUpdateManager.updateAvailable ? .orange : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background((appUpdateManager.updateAvailable ? Color.orange : Color.secondary).opacity(0.08))
    }

    private var packageList: some View {
        List {
            if store.updates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.green)
                    Text(languageManager.text("Aucune mise a jour", "No updates"))
                        .font(.headline)
                    Text(languageManager.text(
                        "La machine est actuellement a jour pour Homebrew et les paquets npm globaux.",
                        "This Mac is currently up to date for Homebrew and global npm packages."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .listRowSeparator(.hidden)
            } else {
                ForEach(store.updates) { package in
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(package.name)
                                    .font(.headline)
                                Text(package.source.rawValue)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(package.source == .homebrew ? Color.blue.opacity(0.12) : Color.green.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                            Text("\(package.kind.capitalized): \(package.currentVersion) -> \(package.latestVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(languageManager.text("Mettre a jour", "Update")) {
                            store.update(package)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isRefreshing || store.isUpdating)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.text("Journal", "Log"))
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(store.logs, id: \.self) { entry in
                        Text(entry)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 140)
        }
        .padding(20)
    }
}
