import Foundation

enum ShellError: LocalizedError {
    case commandNotFound(String)
    case nonZeroExit(command: String, code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let command):
            return L.text(
                "\(command) n'est pas installe.",
                "\(command) is not installed."
            )
        case .nonZeroExit(let command, let code, let stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return L.text(
                    "\(command) a echoue avec le code \(code).",
                    "\(command) failed with exit code \(code)."
                )
            }
            return L.text(
                "\(command) a echoue (\(code)) : \(details)",
                "\(command) failed (\(code)): \(details)"
            )
        }
    }
}

struct ShellOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum Shell {
    private static let askpassHelperPath = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("npm-brew-askpass.sh")

    static func which(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.environment = mergedEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func run(_ launchPath: String, arguments: [String] = []) throws -> ShellOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = mergedEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.nonZeroExit(
                command: ([launchPath] + arguments).joined(separator: " "),
                code: process.terminationStatus,
                stderr: stderr
            )
        }

        return ShellOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    private static func mergedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [environment["PATH"], defaultPath]
            .compactMap { $0 }
            .joined(separator: ":")
        if let askpassPath = ensureAskpassHelper() {
            environment["SUDO_ASKPASS"] = askpassPath
        }
        return environment
    }

    private static func ensureAskpassHelper() -> String? {
        let fileManager = FileManager.default
        let path = askpassHelperPath.path

        if fileManager.isExecutableFile(atPath: path) {
            return path
        }

        let script = """
        #!/bin/sh
        exec /usr/bin/osascript <<'APPLESCRIPT'
        tell application "System Events"
            activate
        end tell
        try
            set dialogResult to display dialog "\(L.text("NPM Brew doit autoriser une commande d'administration Homebrew.", "NPM Brew needs permission to run an administrative Homebrew command."))" default answer "" with title "\(L.text("Authentification administrateur", "Administrator Authentication"))" buttons {"\(L.text("Annuler", "Cancel"))", "OK"} default button "OK" cancel button "\(L.text("Annuler", "Cancel"))" with hidden answer
            return text returned of dialogResult
        on error number -128
            error "\(L.text("Authentification annulee.", "Authentication canceled."))" number 1
        end try
        APPLESCRIPT
        """

        do {
            try script.write(to: askpassHelperPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            return path
        } catch {
            return nil
        }
    }
}
