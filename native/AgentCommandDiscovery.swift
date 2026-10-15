import Foundation
import Darwin

/// A command installation is independent of a desktop application bundle.
struct AgentCommandInstallation: Hashable {
    /// Keep the installed command path, including its launcher symlink.
    let executableURL: URL
    /// The verified npm package root, when the command belongs to one.
    let packageRoot: URL?
}

enum AgentCommandDiscovery {
    /// Passing searchDirectories replaces PATH and all standard fallback roots.
    /// Discovery only inspects files and never starts a command or a shell.
    static func deepseek(
        home: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchDirectories: [URL]? = nil
    ) -> AgentCommandInstallation? {
        for directory in commandDirectories(home: home, environment: environment, override: searchDirectories) {
            let command = directory.appendingPathComponent("dsh")
            guard let resolved = regularExecutable(at: command),
                  let packageRoot = deepseekPackage(containing: resolved) else { continue }
            return AgentCommandInstallation(executableURL: command.standardizedFileURL, packageRoot: packageRoot)
        }
        return nil
    }

    static func grok(
        home: URL,
        dataRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchDirectories: [URL]? = nil
    ) -> AgentCommandInstallation? {
        guard dataRoot.isFileURL, home.isFileURL else { return nil }
        var seenRoots = Set<String>()
        let installationRoots = [dataRoot, home.appendingPathComponent(".grok", isDirectory: true)]
            .map { $0.standardizedFileURL }
            .filter { seenRoots.insert($0.path).inserted }
        for root in installationRoots {
            let primary = root.appendingPathComponent("bin/grok")
            if let resolved = regularExecutable(at: primary), !isApplicationExecutable(resolved) {
                return AgentCommandInstallation(executableURL: primary.standardizedFileURL, packageRoot: nil)
            }
        }

        // The native installer keeps versioned binaries under its data root.
        // A random PATH command with the same name is not enough to identify it.
        let downloads = Set(installationRoots.map {
            $0.appendingPathComponent("downloads", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        })
        for directory in commandDirectories(home: home, environment: environment, override: searchDirectories) {
            let command = directory.appendingPathComponent("grok")
            guard let resolved = regularExecutable(at: command),
                  !isApplicationExecutable(resolved),
                  downloads.contains(resolved.deletingLastPathComponent()),
                  isGrokDownloadName(resolved.lastPathComponent) else { continue }
            return AgentCommandInstallation(executableURL: command.standardizedFileURL, packageRoot: nil)
        }
        return nil
    }

    private static func commandDirectories(
        home: URL, environment: [String: String], override: [URL]?
    ) -> [URL] {
        let candidates: [URL]
        if let override {
            candidates = override
        } else {
            // Ignore empty and relative PATH entries; they depend on the app's
            // working directory rather than an installed command location.
            let pathRoots = (environment["PATH"] ?? "").split(separator: ":")
                .filter { $0.hasPrefix("/") }
                .map { URL(fileURLWithPath: String($0), isDirectory: true) }
            candidates = pathRoots + [
                home.appendingPathComponent(".npm-global/bin", isDirectory: true),
                home.appendingPathComponent(".local/bin", isDirectory: true),
                URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
                URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
            ]
        }
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard candidate.isFileURL else { return nil }
            let directory = candidate.standardizedFileURL
            guard seen.insert(directory.path).inserted else { return nil }
            return directory
        }
    }

    private static func regularExecutable(at command: URL) -> URL? {
        guard command.isFileURL else { return nil }
        let resolved = command.standardizedFileURL.resolvingSymlinksInPath()
        guard let identity = SkillFileIdentity.identity(at: resolved),
              identity.fileType == mode_t(S_IFREG),
              FileManager.default.isExecutableFile(atPath: resolved.path) else { return nil }
        return resolved
    }

    private static func deepseekPackage(containing executable: URL) -> URL? {
        var directory = executable.deletingLastPathComponent()
        for _ in 0..<12 {
            let manifest = directory.appendingPathComponent("package.json")
            if SkillFileIdentity.identity(at: manifest) != nil {
                guard let data = SkillFileSafety.completeManifest(at: manifest),
                      let metadata = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      metadata["name"] as? String == "@deepseek-ai/dsh" else { return nil }
                let entry = (metadata["bin"] as? [String: String])?["dsh"]
                    ?? (metadata["bin"] as? String)
                guard let entry, !entry.isEmpty, !entry.hasPrefix("/"), !entry.hasPrefix("~") else { return nil }
                let mapped = directory.appendingPathComponent(entry).standardizedFileURL
                guard mapped.path.hasPrefix(directory.path + "/"),
                      mapped.resolvingSymlinksInPath().standardizedFileURL == executable else { return nil }
                return directory
            }
            guard directory.path != "/" else { break }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private static func isApplicationExecutable(_ url: URL) -> Bool {
        url.pathComponents.contains { $0.lowercased().hasSuffix(".app") }
    }

    private static func isGrokDownloadName(_ name: String) -> Bool {
        name.range(of: #"^grok-(?:[0-9]+\.[0-9]+\.[0-9]+(?:[.-][A-Za-z0-9]+)*-)?macos-(?:aarch64|arm64|x64|x86_64)$"#,
                   options: .regularExpression) != nil
    }
}
