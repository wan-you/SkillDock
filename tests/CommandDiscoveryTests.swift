import Foundation
import Darwin

@main
struct CommandDiscoveryTests {
    private struct Failure: Error { let message: String }
    private static var assertions = 0

    private static func require(_ condition: Bool, _ message: String) throws {
        assertions += 1
        if !condition { throw Failure(message: message) }
    }

    static func main() {
        do {
            try run()
            print("PASS CommandDiscovery: \(assertions) isolated installation checks")
        } catch let failure as Failure {
            fputs("FAIL CommandDiscovery: \(failure.message)\n", stderr)
            exit(1)
        } catch {
            fputs("FAIL CommandDiscovery: fixture setup or filesystem operation failed\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("skilldock-commands-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let dataRoot = home.appendingPathComponent(".grok", isDirectory: true)
        let environment = ["PATH": bin.path]
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)

        func directory(_ path: String) throws -> URL {
            let result = root.appendingPathComponent(path, isDirectory: true)
            try fm.createDirectory(at: result, withIntermediateDirectories: true)
            return result
        }
        func executable(_ url: URL, mode: mode_t = 0o755) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Discovery must only inspect this file, never execute it.
            try Data("#!/bin/sh\nexit 97\n".utf8).write(to: url)
            try require(Darwin.chmod(url.path, mode) == 0, "could not set fixture permissions")
        }
        func manifest(_ package: URL, name: String = "@deepseek-ai/dsh", entry: Any = ["dsh": "lib/bin.js"]) throws {
            let data = try JSONSerialization.data(withJSONObject: ["name": name, "version": "0.2.0-rc.2", "bin": entry])
            try data.write(to: package.appendingPathComponent("package.json"))
        }
        func deepseek(_ directories: [URL] = [bin]) -> AgentCommandInstallation? {
            AgentCommandDiscovery.deepseek(home: home, environment: environment, searchDirectories: directories)
        }
        func grok(_ directories: [URL] = [bin]) -> AgentCommandInstallation? {
            AgentCommandDiscovery.grok(home: home, dataRoot: dataRoot, environment: environment, searchDirectories: directories)
        }

        try require(deepseek() == nil && grok() == nil, "missing commands must not count as installed")
        try require(!fm.fileExists(atPath: dataRoot.path), "discovery must not create data directories")
        let package = try directory("packages/@deepseek-ai/dsh")
        let entry = package.appendingPathComponent("lib/bin.js")
        let dsh = bin.appendingPathComponent("dsh")
        try executable(entry)
        try manifest(package)
        try fm.createSymbolicLink(at: dsh, withDestinationURL: entry)
        let installed = deepseek()
        try require(installed?.executableURL == dsh, "the installed dsh launcher path must be preserved")
        try require(installed?.packageRoot == package.resolvingSymlinksInPath(), "the verified package root must be returned")
        try require(deepseek([]) == nil, "injected roots must replace PATH and all system fallback roots")
        try require(deepseek([URL(string: "https://example.invalid/bin")!]) == nil, "non-file search roots must be ignored")

        try manifest(package, name: "unrelated/dsh")
        try require(deepseek() == nil, "a different package using the same command name must be rejected")
        try manifest(package, entry: ["dsh": "lib/other.js"])
        try require(deepseek() == nil, "the dsh bin mapping must match the resolved entry")
        try manifest(package, entry: ["not-dsh": "lib/bin.js"])
        try require(deepseek() == nil, "a package without a dsh bin mapping must be rejected")
        try manifest(package, entry: "./lib/bin.js")
        try require(deepseek() != nil, "npm's string bin form must remain supported for the verified package name")
        try manifest(package, entry: ["dsh": entry.path])
        try require(deepseek() == nil, "absolute bin mappings must be rejected")
        try manifest(package, entry: ["dsh": "../dsh/lib/bin.js"])
        try require(deepseek() != nil, "a normalized mapping still inside the same package may identify its entry")
        try manifest(package, entry: ["dsh": "../../outside.js"])
        try require(deepseek() == nil, "a bin mapping outside the package must be rejected")
        try Data("invalid json".utf8).write(to: package.appendingPathComponent("package.json"))
        try require(deepseek() == nil, "malformed package manifests must be rejected")
        try Data(repeating: 0x20, count: SkillFileSafety.manifestByteLimit + 1)
            .write(to: package.appendingPathComponent("package.json"))
        try require(deepseek() == nil, "oversized package manifests must be rejected by the bounded reader")
        try manifest(package)
        let nestedManifest = entry.deletingLastPathComponent().appendingPathComponent("package.json")
        try Data(#"{"name":"unrelated-package","bin":{"dsh":"bin.js"}}"#.utf8).write(to: nestedManifest)
        try require(deepseek() == nil, "a nested unrelated package must not borrow its ancestor's identity")
        try fm.removeItem(at: nestedManifest)
        try require(Darwin.chmod(entry.path, 0o644) == 0, "could not remove fixture executable permissions")
        try require(deepseek() == nil, "non-executable files must not count as a CLI installation")
        try require(Darwin.chmod(entry.path, 0o755) == 0, "could not restore fixture executable permissions")
        try fm.removeItem(at: dsh)
        try fm.createSymbolicLink(at: dsh, withDestinationURL: root.appendingPathComponent("missing-entry"))
        try require(deepseek() == nil, "dangling command links must be ignored")
        try fm.removeItem(at: dsh)
        try fm.createDirectory(at: dsh, withIntermediateDirectories: false)
        try require(deepseek() == nil, "an executable directory named dsh must be rejected")
        try fm.removeItem(at: dsh)
        try require(Darwin.mkfifo(dsh.path, 0o755) == 0, "could not create FIFO fixture")
        try require(deepseek() == nil, "special files named dsh must be rejected without opening them")
        try fm.removeItem(at: dsh)
        try executable(dsh)
        try require(deepseek() == nil, "a standalone unrelated dsh executable must not count as Harness")

        let downloaded = dataRoot.appendingPathComponent("downloads/grok-1.0.52-macos-aarch64")
        let primary = dataRoot.appendingPathComponent("bin/grok")
        let grokCommand = bin.appendingPathComponent("grok")
        try executable(downloaded)
        try fm.createDirectory(at: primary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: primary, withDestinationURL: downloaded)
        try require(grok([])?.executableURL == primary, "the native Grok installation must be found without PATH")
        try require(grok()?.packageRoot == nil, "native Grok must not pretend to be an npm package")
        let customDataRoot = root.appendingPathComponent("custom-grok-home", isDirectory: true)
        try require(AgentCommandDiscovery.grok(home: home, dataRoot: customDataRoot,
                                               environment: environment, searchDirectories: [])?.executableURL == primary,
                    "a data-root override must still find the default Grok binary installation")
        try require(!fm.fileExists(atPath: customDataRoot.path), "a custom data-root lookup must not create it")
        let customPrimary = customDataRoot.appendingPathComponent("bin/grok")
        try executable(customPrimary)
        try require(AgentCommandDiscovery.grok(home: home, dataRoot: customDataRoot,
                                               environment: environment, searchDirectories: [])?.executableURL == customPrimary,
                    "the explicit data-root installation must take priority over the default binary")
        try fm.removeItem(at: customPrimary)
        try fm.removeItem(at: primary)
        try fm.createSymbolicLink(at: grokCommand, withDestinationURL: downloaded)
        try require(grok()?.executableURL == grokCommand, "a PATH link to the known Grok downloads directory must be supported")
        try require(AgentCommandDiscovery.grok(home: home, dataRoot: customDataRoot,
                                               environment: environment, searchDirectories: [bin])?.executableURL == grokCommand,
                    "a data-root override must retain PATH links into the default downloads installation")
        try require(Darwin.chmod(downloaded.path, 0o644) == 0, "could not remove downloaded binary permissions")
        try require(grok() == nil, "a PATH link to a non-executable download must be ignored")
        try require(Darwin.chmod(downloaded.path, 0o755) == 0, "could not restore downloaded binary permissions")
        try fm.removeItem(at: grokCommand)
        try executable(grokCommand)
        try require(grok() == nil, "an unrelated executable named grok on PATH must not count as installed")
        try fm.removeItem(at: grokCommand)
        let similarlyNamed = dataRoot.appendingPathComponent("downloads/groktest")
        try executable(similarlyNamed)
        try fm.createSymbolicLink(at: grokCommand, withDestinationURL: similarlyNamed)
        try require(grok() == nil, "an arbitrary file in downloads must not impersonate the native binary")
        try fm.removeItem(at: grokCommand)
        let applicationBinary = root.appendingPathComponent("Grok Bot.app/Contents/MacOS/Grok Bot")
        try executable(applicationBinary)
        try fm.createSymbolicLink(at: primary, withDestinationURL: applicationBinary)
        try require(grok() == nil, "Grok Bot.app must not be treated as the Grok CLI")
        try fm.removeItem(at: primary)
        try executable(primary, mode: 0o644)
        try require(grok() == nil, "a non-executable primary Grok file must be ignored")
        try fm.removeItem(at: primary)
        try fm.createDirectory(at: primary, withIntermediateDirectories: false)
        try require(grok() == nil, "a directory named grok must be ignored")
        try fm.removeItem(at: primary)
        try fm.createSymbolicLink(at: primary, withDestinationURL: root.appendingPathComponent("missing-grok"))
        try require(grok() == nil, "a dangling primary Grok command must be ignored")
        try fm.removeItem(at: primary)
        try executable(primary)
        try require(grok([])?.executableURL == primary, "a regular primary Grok executable must be supported")
        try require(AgentCommandDiscovery.grok(home: home, dataRoot: URL(string: "https://example.invalid")!,
                                               environment: environment, searchDirectories: []) == nil,
                    "non-file Grok data roots must be ignored")
    }
}
