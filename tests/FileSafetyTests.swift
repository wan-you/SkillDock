import Foundation
import Darwin

@main
struct FileSafetyTests {
    private struct Failure: Error {
        let message: String
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    static func main() {
        do {
            try run()
            print("PASS FileSafety: bounded reads, special files, symlinks, and filesystem identities")
        } catch let failure as Failure {
            fputs("FAIL FileSafety: \(failure.message)\n", stderr)
            exit(1)
        } catch {
            fputs("FAIL FileSafety: fixture setup or filesystem operation failed\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let fm = FileManager.default
        // Keep the Unix socket path below sockaddr_un's path-length limit.
        let name = "sd-" + UUID().uuidString.prefix(16)
        let root = fm.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        func url(_ name: String, isDirectory: Bool = false) -> URL {
            root.appendingPathComponent(name, isDirectory: isDirectory)
        }

        let smallDefinition = Data("---\nname: Unicode 技能\ndescription: 保持完整\n---\nbody\n".utf8)
        try smallDefinition.write(to: url("small.md"))
        var largeDefinition = smallDefinition
        largeDefinition.append(Data(repeating: 0x78, count: 512 * 1024))
        try largeDefinition.write(to: url("large.md"))
        let prefix = SkillFileSafety.metadataPrefix(at: url("large.md"))
        try require(prefix?.count == SkillFileSafety.metadataByteLimit,
                    "large SKILL.md must be limited to the metadata prefix")
        let prefixText = prefix.flatMap { String(data: $0, encoding: .utf8) }
        try require(prefixText?.contains("name: Unicode 技能") == true,
                    "Unicode front matter must remain readable")
        try require(SkillFileSafety.metadataPrefix(at: url("small.md")) == smallDefinition,
                    "small files must be read completely")

        let manifest = try JSONSerialization.data(withJSONObject: [
            "skills": [["name": "技能-𝔸", "creatorType": "anthropic"]],
            "lastUpdated": 123.4,
            "payload": String(repeating: "x", count: 300 * 1024)
        ])
        try manifest.write(to: url("manifest.json"))
        let complete = SkillFileSafety.completeManifest(at: url("manifest.json"))
        try require(complete == manifest, "manifest reads must not truncate at the metadata limit")
        let decoded = try JSONSerialization.jsonObject(with: complete ?? Data()) as? [String: Any]
        let entries = decoded?["skills"] as? [[String: Any]]
        try require(entries?.first?["name"] as? String == "技能-𝔸",
                    "valid Unicode JSON must survive the complete read")

        // A valid JSON string whose serialized length is exactly the limit.
        var exactManifest = Data([0x22])
        exactManifest.append(Data(repeating: 0x78, count: SkillFileSafety.manifestByteLimit - 2))
        exactManifest.append(0x22)
        try exactManifest.write(to: url("exact.json"))
        try require(SkillFileSafety.completeManifest(at: url("exact.json")) == exactManifest,
                    "a manifest exactly at the limit must be accepted")
        exactManifest.append(0x20)
        try exactManifest.write(to: url("oversize.json"))
        try require(SkillFileSafety.completeManifest(at: url("oversize.json")) == nil,
                    "a manifest one byte above the limit must be rejected")

        try fm.createSymbolicLink(at: url("linked.md"), withDestinationURL: url("small.md"))
        try require(SkillFileSafety.metadataPrefix(at: url("linked.md")) == smallDefinition,
                    "regular-file symbolic links must remain supported")
        try require(SkillFileSafety.completeManifest(at: url("linked.md")) == smallDefinition,
                    "the complete reader must also support regular-file symbolic links")

        try fm.createDirectory(at: url("directory", isDirectory: true), withIntermediateDirectories: false)
        try require(Darwin.mkfifo(url("fifo").path, mode_t(0o600)) == 0, "could not create FIFO fixture")
        let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try require(socketDescriptor >= 0, "could not create socket fixture")
        defer { Darwin.close(socketDescriptor) }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let socketPath = Array(url("s").path.utf8) + [0]
        try require(socketPath.count <= MemoryLayout.size(ofValue: address.sun_path),
                    "temporary socket path is too long")
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: socketPath) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try require(bound == 0, "could not bind socket fixture")
        for name in ["fifo", "s", "directory", "missing"] {
            let start = ProcessInfo.processInfo.systemUptime
            try require(SkillFileSafety.metadataPrefix(at: url(name)) == nil,
                        "metadata reader must reject non-regular or missing files")
            try require(SkillFileSafety.completeManifest(at: url(name)) == nil,
                        "manifest reader must reject non-regular or missing files")
            try require(ProcessInfo.processInfo.systemUptime - start < 1,
                        "special-file refusal must not block")
        }
        let remote = URL(string: "https://example.invalid/SKILL.md")!
        try require(SkillFileSafety.metadataPrefix(at: remote) == nil
                    && SkillFileSafety.completeManifest(at: remote) == nil
                    && SkillFileIdentity.identity(at: remote) == nil,
                    "non-file URLs must be rejected without opening them")

        guard let original = SkillFileIdentity.identity(at: url("small.md")) else {
            throw Failure(message: "regular-file identity was not captured")
        }
        try require(!original.isDirectory && !original.isSymbolicLink,
                    "regular-file type was incorrectly classified")
        try Data("ordinary edit".utf8).write(to: url("small.md"))
        try require(SkillFileIdentity.identity(at: url("small.md")) == original,
                    "ordinary in-place edits must preserve identity")
        try require(Darwin.chmod(url("small.md").path, mode_t(0o400)) == 0,
                    "could not change fixture permissions")
        try require(SkillFileIdentity.identity(at: url("small.md")) == original,
                    "permission changes must not change identity")
        try fm.moveItem(at: url("small.md"), to: url("old.md"))
        try smallDefinition.write(to: url("small.md"))
        try require(SkillFileIdentity.identity(at: url("small.md")) != original,
                    "a replacement inode must invalidate a captured identity")
        try require(SkillFileIdentity.identity(at: url("directory", isDirectory: true))?.isDirectory == true,
                    "directories must be classified from file-type bits")
        try require(SkillFileIdentity.identity(at: url("linked.md", isDirectory: true))?.isSymbolicLink == true,
                    "lstat must preserve a final symbolic link even with a directory URL hint")
        try require(SkillFileIdentity.identity(at: url("missing")) == nil,
                    "missing entries must have no identity")
    }
}
