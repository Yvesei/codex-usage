import Foundation

struct CodexExecutableLocator {
    private let fileManager = FileManager.default

    func find() -> URL? {
        let launchers = launcherCandidates()

        // npm installs a JavaScript launcher alongside a native executable.
        // Use the native executable so Finder does not need Node on its PATH.
        for launcher in launchers {
            if let executable = nativeExecutable(for: launcher) {
                return executable
            }
        }

        for launcher in launchers {
            if fileManager.isExecutableFile(atPath: launcher.path) {
                return launcher
            }
        }

        return nil
    }

    func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        let executableDirectory = executable.deletingLastPathComponent().path
        let nodeDirectories = installedNodeVersions().map { version in
            version.appendingPathComponent("bin").path
        }
        var paths = [executableDirectory]
        paths.append(contentsOf: nodeDirectories)
        paths.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        paths.append(existingPath)
        environment["PATH"] = paths.joined(separator: ":")
        return environment
    }

    private func launcherCandidates() -> [URL] {
        var candidates: [URL] = []
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""

        for directory in path.split(separator: ":") {
            let url = URL(fileURLWithPath: String(directory), isDirectory: true)
            candidates.append(url.appendingPathComponent("codex"))
        }

        for version in installedNodeVersions() {
            candidates.append(version.appendingPathComponent("bin/codex"))
        }

        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".local/bin/codex"))
        candidates.append(home.appendingPathComponent("Library/pnpm/codex"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/usr/bin/codex"))
        return candidates
    }

    private func installedNodeVersions() -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let directory = home.appendingPathComponent(".nvm/versions/node")
        let versions = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return (versions ?? []).sorted { first, second in
            first.lastPathComponent.localizedStandardCompare(second.lastPathComponent) == .orderedDescending
        }
    }

    private func nativeExecutable(for launcher: URL) -> URL? {
        let resolvedLauncher = launcher.resolvingSymlinksInPath()
        let launcherName = resolvedLauncher.lastPathComponent

        guard launcherName == "codex.js" else {
            return nil
        }

        let package = resolvedLauncher.deletingLastPathComponent().deletingLastPathComponent()
        let executable = package.appendingPathComponent(nativePackagePath)

        guard fileManager.isExecutableFile(atPath: executable.path) else {
            return nil
        }

        return executable
    }

    private var nativePackagePath: String {
        #if arch(arm64)
        return "node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
        #else
        return "node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex"
        #endif
    }
}
