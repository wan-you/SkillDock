import Foundation
import Darwin

/// The identity of the directory entry itself, including a final symbolic link.
/// Permissions and modification dates are deliberately excluded so an ordinary
/// edit does not change the identity of a skill already shown in the interface.
struct SkillFileIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
    let fileType: mode_t

    var isDirectory: Bool { fileType == mode_t(S_IFDIR) }
    var isSymbolicLink: Bool { fileType == mode_t(S_IFLNK) }

    static func identity(at url: URL) -> SkillFileIdentity? {
        guard url.isFileURL else { return nil }
        var status = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &status)
        }
        guard result == 0 else { return nil }
        return SkillFileIdentity(device: status.st_dev, inode: status.st_ino,
                                 fileType: status.st_mode & mode_t(S_IFMT))
    }
}

enum SkillFileSafety {
    static let metadataByteLimit = 256 * 1024
    static let manifestByteLimit = 4 * 1024 * 1024

    /// Resolve the existing ancestor before appending a not-yet-created path.
    /// Foundation does not reliably resolve ancestor links when the leaf is absent.
    static func canonicalLocation(at url: URL) -> URL {
        guard url.isFileURL else { return url }
        var ancestor = url.standardizedFileURL
        var missingComponents: [String] = []
        while ancestor.path != "/" && SkillFileIdentity.identity(at: ancestor) == nil {
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }

    /// Read only enough of SKILL.md to inspect its front matter. A long body
    /// does not increase the amount of memory allocated by this reader.
    static func metadataPrefix(at url: URL) -> Data? {
        readRegularFile(at: url, limit: metadataByteLimit, requireComplete: false)
    }

    /// A manifest must be small enough to read and parse in its entirety.
    static func completeManifest(at url: URL) -> Data? {
        readRegularFile(at: url, limit: manifestByteLimit, requireComplete: true)
    }

    private static func readRegularFile(at url: URL, limit: Int, requireComplete: Bool) -> Data? {
        guard url.isFileURL else { return nil }
        // Per-skill links and linked SKILL.md files are supported. Refuse a
        // replacement symbolic link at the resolved final component when open
        // races with a local filesystem change.
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let descriptor = resolved.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var initial = stat()
        guard Darwin.fstat(descriptor, &initial) == 0,
              initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              initial.st_size >= 0 else { return nil }
        if requireComplete && initial.st_size > off_t(limit) { return nil }

        // One extra byte detects a manifest that grows past the limit while
        // being read. The allocation is bounded even if the file grows forever.
        let readLimit = requireComplete ? limit + 1 : limit
        var data = Data(count: readLimit)
        let byteCount: Int? = data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return nil }
            var total = 0
            while total < readLimit {
                let count = Darwin.read(descriptor, base.advanced(by: total), readLimit - total)
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR { continue }
                    return nil
                }
                total += count
            }
            return total
        }
        guard let byteCount else { return nil }
        if requireComplete {
            var final = stat()
            guard byteCount <= limit,
                  Darwin.fstat(descriptor, &final) == 0,
                  initial.st_size == off_t(byteCount),
                  final.st_size == off_t(byteCount) else { return nil }
        }
        data.removeSubrange(byteCount..<data.count)
        return data
    }
}
