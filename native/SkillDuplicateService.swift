import Foundation
import CryptoKit
import Darwin

struct SkillDuplicateCandidate: Identifiable {
    let id: String
    let path: URL
    let name: String
    let location: String
    let canReplace: Bool
    let sourcePriority: Int
    fileprivate var capture: DuplicateCapture?

    init(id: String, path: URL, name: String, location: String, canReplace: Bool, sourcePriority: Int) {
        self.id = id
        self.path = path
        self.name = name
        self.location = location
        self.canReplace = canReplace
        self.sourcePriority = sourcePriority
    }
}

struct SkillDuplicateGroup: Identifiable {
    let id: String
    let source: SkillDuplicateCandidate
    let copies: [SkillDuplicateCandidate]
    var fingerprint: String { id }
}

struct SkillDuplicateSkip {
    let path: URL
    let reason: String
}

struct SkillDuplicateScan {
    let groups: [SkillDuplicateGroup]
    let skipped: [SkillDuplicateSkip]
    let scannedCount: Int
}

struct SkillDuplicatePlanEntry {
    let source: SkillDuplicateCandidate
    let copy: SkillDuplicateCandidate
    let fingerprint: String
}

struct SkillOrganizationRecord: Codable {
    let sourcePath: String
    let copyPath: String
    let backupPath: String
    fileprivate let original: DuplicateCapture
    fileprivate let linkIdentity: DuplicateIdentity
}

struct SkillOrganizationBatch: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let records: [SkillOrganizationRecord]
    fileprivate(set) var restoredAt: Date?
    fileprivate var completed = false
    fileprivate var restoring = false
}

private struct DuplicateIdentity: Codable, Equatable, Hashable {
    let device: UInt64
    let inode: UInt64
    let type: UInt32

    init(_ status: stat) {
        device = UInt64(bitPattern: Int64(status.st_dev))
        inode = UInt64(status.st_ino)
        type = UInt32(status.st_mode & mode_t(S_IFMT))
    }
}

fileprivate struct DuplicateCapture: Codable {
    let path: String
    let parentPath: String
    fileprivate let identity: DuplicateIdentity
    fileprivate let parentIdentity: DuplicateIdentity
    let fingerprint: String
    let revision: String
}

private struct DuplicateFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Inspects complete directory trees and replaces verified copies with links.
/// A scan never changes skills. Every replacement retains its original directory
/// in a journaled backup, which also supports recovery after restarting the app.
enum SkillDuplicateService {
    private static let operationLock = NSLock()
    private static let manifestLimit = 16 * 1024 * 1024

    static func scan(candidates: [SkillDuplicateCandidate]) throws -> SkillDuplicateScan {
        try Task.checkCancellation()
        var buckets: [String: [SkillDuplicateCandidate]] = [:]
        var seen = Set<DuplicateIdentity>()
        var skipped: [SkillDuplicateSkip] = []
        var scanned = 0
        for var candidate in candidates.sorted(by: preferred) {
            try Task.checkCancellation()
            do {
                let capture = try inspect(candidate.path)
                guard seen.insert(capture.identity).inserted else { continue }
                candidate.capture = capture
                buckets[capture.fingerprint, default: []].append(candidate)
                scanned += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skipped.append(SkillDuplicateSkip(path: candidate.path, reason: error.localizedDescription))
            }
        }
        let groups = buckets.compactMap { fingerprint, candidates -> SkillDuplicateGroup? in
            let sorted = candidates.sorted(by: preferred)
            guard let source = sorted.first, sorted.count > 1 else { return nil }
            return SkillDuplicateGroup(id: fingerprint, source: source, copies: Array(sorted.dropFirst()))
        }.sorted { preferred($0.source, $1.source) }
        return SkillDuplicateScan(groups: groups, skipped: skipped, scannedCount: scanned)
    }

    static func convert(entries: [SkillDuplicatePlanEntry], backupRoot: URL) throws -> SkillOrganizationBatch {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard !entries.isEmpty else { throw failure("No copies were selected.") }
        let entries = entries.sorted { $0.copy.path.path < $1.copy.path.path }
        try validatePlan(entries)
        try rejectBackupOverlap(SkillFileSafety.canonicalLocation(at: backupRoot), entries: entries)
        let root = try openBackupRoot(backupRoot, create: true)
        defer { Darwin.close(root.fd) }
        let lock = try lockRoot(root.fd)
        defer { Darwin.lockf(lock, F_ULOCK, 0); Darwin.close(lock) }
        try rejectBackupOverlap(root.url, entries: entries)
        // Validate the whole selection before creating a journal or moving a copy.
        for entry in entries { try validate(entry) }

        let batchID = UUID().uuidString.lowercased()
        guard Darwin.mkdirat(root.fd, batchID, 0o700) == 0 else { throw systemFailure("Create backup batch") }
        let batchFD = Darwin.openat(root.fd, batchID, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard batchFD >= 0 else { throw systemFailure("Open backup batch") }
        defer { Darwin.close(batchFD) }
        let batchURL = root.url.appendingPathComponent(batchID, isDirectory: true)
        var records: [SkillOrganizationRecord] = []
        do {
            for (index, entry) in entries.enumerated() {
                let target = entry.source.capture!.path
                let stageName = "link-\(index)"
                guard Darwin.symlinkat(target, batchFD, stageName) == 0 else { throw systemFailure("Stage skill link") }
                let link = try status(at: batchFD, name: stageName)
                records.append(SkillOrganizationRecord(sourcePath: target, copyPath: entry.copy.capture!.path,
                    backupPath: batchURL.appendingPathComponent("original-\(index)", isDirectory: true).path,
                    original: entry.copy.capture!, linkIdentity: DuplicateIdentity(link)))
            }
        } catch {
            // Only staged links exist at this point; no skill has moved.
            for index in entries.indices { _ = Darwin.unlinkat(batchFD, "link-\(index)", 0) }
            _ = Darwin.unlinkat(root.fd, batchID, AT_REMOVEDIR)
            throw error
        }
        var batch = SkillOrganizationBatch(id: batchID, createdAt: Date(), records: records)
        do {
            try writeManifest(batch, directory: batchFD)
            guard Darwin.fsync(root.fd) == 0 else { throw systemFailure("Save backup batch") }
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                try validateRoot(root)
                try validate(entry)
                let record = records[index]
                let parent = try openParent(record.original)
                defer { Darwin.close(parent) }
                try requireIdentity(parent, name: URL(fileURLWithPath: record.copyPath).lastPathComponent,
                                    expected: record.original.identity)
                try renameExclusive(fromFD: parent, name: URL(fileURLWithPath: record.copyPath).lastPathComponent,
                                    toFD: batchFD, name: "original-\(index)")
                guard Darwin.fsync(parent) == 0, Darwin.fsync(batchFD) == 0 else { throw systemFailure("Save retained original") }
                // Catch changes made between the last read and the atomic move.
                let moved = try inspect(URL(fileURLWithPath: record.backupPath))
                guard moved.identity == record.original.identity,
                      moved.fingerprint == entry.fingerprint,
                      moved.revision == record.original.revision else {
                    throw failure("A copy changed while it was being organized.")
                }
                try requireUnchanged(entry.source)
                try renameExclusive(fromFD: batchFD, name: "link-\(index)",
                                    toFD: parent, name: URL(fileURLWithPath: record.copyPath).lastPathComponent)
                guard Darwin.fsync(parent) == 0 else { throw systemFailure("Save skill link") }
                guard Darwin.fsync(batchFD) == 0 else { throw systemFailure("Save skill backup") }
            }
            batch.completed = true
            try writeManifest(batch, directory: batchFD)
            return batch
        } catch {
            // Recovery uses identities and exclusive renames, so a concurrent user
            // edit is never removed or overwritten, even during rollback.
            let originalError = error
            do {
                try recover(batch, directory: batchFD, allowPending: true)
                var reverted = batch
                reverted.restoredAt = Date()
                try writeManifest(reverted, directory: batchFD)
            } catch {
                throw failure("\(originalError.localizedDescription) The retained originals are in \(batchURL.path). Recovery stopped because a path changed: \(error.localizedDescription)")
            }
            throw originalError
        }
    }

    static func restore(batch: SkillOrganizationBatch, backupRoot: URL) throws {
        operationLock.lock()
        defer { operationLock.unlock() }
        let root = try openBackupRoot(backupRoot, create: false)
        defer { Darwin.close(root.fd) }
        let lock = try lockRoot(root.fd)
        defer { Darwin.lockf(lock, F_ULOCK, 0); Darwin.close(lock) }
        let directory = try openBatch(batch.id, root: root)
        defer { Darwin.close(directory) }
        var stored = try readManifest(directory: directory)
        guard stored.id == batch.id, stored.restoredAt == nil else { throw failure("This organization has already been restored.") }
        try validateBatch(stored, root: root.url)
        // Check every entry before restoring any, to keep ordinary conflicts atomic.
        try preflightRecovery(stored, directory: directory, allowPending: !stored.completed || stored.restoring)
        // Persist undo intent before moving the first link, so a restarted app
        // can finish an undo whose earlier records were already restored.
        stored.restoring = true
        try writeManifest(stored, directory: directory)
        try recover(stored, directory: directory, allowPending: true)
        var restored = stored
        restored.restoredAt = Date()
        try writeManifest(restored, directory: directory)
    }

    static func loadLastBatch(backupRoot: URL) throws -> SkillOrganizationBatch? {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard SkillFileIdentity.identity(at: backupRoot) != nil else { return nil }
        let root = try openBackupRoot(backupRoot, create: false)
        defer { Darwin.close(root.fd) }
        let lock = try lockRoot(root.fd)
        defer { Darwin.lockf(lock, F_ULOCK, 0); Darwin.close(lock) }
        var batches: [SkillOrganizationBatch] = []
        for name in try names(in: root.fd) where UUID(uuidString: name) != nil {
            guard let fd = try? openBatch(name, root: root) else { continue }
            defer { Darwin.close(fd) }
            // A crash while staging links may leave a directory before its
            // first journal was written. Such a directory contains no moved
            // originals and must not hide older, recoverable organizations.
            guard let batch = try? readManifest(directory: fd), batch.id == name,
                  (try? validateBatch(batch, root: root.url)) != nil else { continue }
            if batch.restoredAt == nil { batches.append(batch) }
        }
        return batches.max { $0.createdAt < $1.createdAt }
    }

    private static func preferred(_ left: SkillDuplicateCandidate, _ right: SkillDuplicateCandidate) -> Bool {
        if left.sourcePriority != right.sourcePriority { return left.sourcePriority < right.sourcePriority }
        return left.path.standardizedFileURL.path < right.path.standardizedFileURL.path
    }

    private static func validatePlan(_ entries: [SkillDuplicatePlanEntry]) throws {
        var copies = Set<String>()
        var sources = Set<String>()
        for entry in entries {
            guard entry.copy.canReplace, let source = entry.source.capture, let copy = entry.copy.capture,
                  source.fingerprint == entry.fingerprint, copy.fingerprint == entry.fingerprint,
                  source.identity != copy.identity, copies.insert(copy.path).inserted else {
                throw failure("Select distinct, replaceable copies from a current duplicate scan.")
            }
            sources.insert(source.path)
        }
        guard sources.isDisjoint(with: copies) else { throw failure("An original cannot also be replaced in the same organization.") }
        let paths = Array(sources.union(copies)).sorted()
        for (index, path) in paths.enumerated() {
            for other in paths.dropFirst(index + 1) where overlap(path, other) {
                throw failure("Skill folders overlap: \(path) and \(other).")
            }
        }
    }

    private static func rejectBackupOverlap(_ root: URL, entries: [SkillDuplicatePlanEntry]) throws {
        for entry in entries {
            for path in [entry.source.capture!.path, entry.copy.capture!.path] where overlap(root.path, path) {
                throw failure("The backup directory overlaps a selected skill.")
            }
        }
    }

    private static func validate(_ entry: SkillDuplicatePlanEntry) throws {
        try requireUnchanged(entry.source)
        try requireUnchanged(entry.copy)
    }

    private static func requireUnchanged(_ candidate: SkillDuplicateCandidate) throws {
        guard let captured = candidate.capture else { throw failure("Scan the skills before organizing them.") }
        let current = try inspect(candidate.path)
        guard current.path == captured.path, current.parentPath == captured.parentPath,
              current.identity == captured.identity, current.parentIdentity == captured.parentIdentity,
              current.fingerprint == captured.fingerprint, current.revision == captured.revision else {
            throw failure("A skill changed after the scan: \(candidate.path.path). Scan again.")
        }
    }

    private static func inspect(_ url: URL, cancellable: Bool = true) throws -> DuplicateCapture {
        if cancellable { try Task.checkCancellation() }
        guard url.isFileURL else { throw failure("The skill must be a local directory.") }
        let logical = url.standardizedFileURL
        guard let entry = SkillFileIdentity.identity(at: logical), entry.isDirectory else {
            throw failure("Only real skill directories can be compared.")
        }
        let parentURL = logical.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let path = parentURL.appendingPathComponent(logical.lastPathComponent, isDirectory: true)
        let parent = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw systemFailure("Open skill parent") }
        defer { Darwin.close(parent) }
        let parentStat = try status(parent)
        let fd = Darwin.openat(parent, path.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw systemFailure("Open skill directory") }
        defer { Darwin.close(fd) }
        let before = try status(fd)
        guard DuplicateIdentity(before) == DuplicateIdentity(try status(at: parent, name: path.lastPathComponent)) else {
            throw failure("The skill directory changed during inspection.")
        }
        var content = SHA256()
        var revision = SHA256()
        try walk(directory: fd, relative: "", content: &content, revision: &revision, cancellable: cancellable)
        try requireIdentity(parent, name: path.lastPathComponent, expected: DuplicateIdentity(before))
        guard SkillFileIdentity.identity(at: logical) == entry,
              logical.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == parentURL.path else {
            throw failure("The skill location changed during inspection.")
        }
        return DuplicateCapture(path: path.path, parentPath: parentURL.path, identity: DuplicateIdentity(before),
                                parentIdentity: DuplicateIdentity(parentStat), fingerprint: hex(content.finalize()),
                                revision: hex(revision.finalize()))
    }

    private static func walk(directory: Int32, relative: String, content: inout SHA256, revision: inout SHA256, cancellable: Bool) throws {
        if cancellable { try Task.checkCancellation() }
        let before = try status(directory)
        feed("directory", to: &content)
        feed(relative, to: &content)
        feed(UInt64(before.st_mode & 0o111), to: &content)
        feedRevision(before, relative: relative, to: &revision)
        for name in try names(in: directory) {
            if cancellable { try Task.checkCancellation() }
            let path = relative.isEmpty ? name : relative + "/" + name
            let entry = try status(at: directory, name: name)
            let type = entry.st_mode & mode_t(S_IFMT)
            if type == mode_t(S_IFDIR) {
                let child = Darwin.openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else { throw systemFailure("Open nested directory") }
                defer { Darwin.close(child) }
                guard DuplicateIdentity(try status(child)) == DuplicateIdentity(entry) else { throw failure("A directory changed during inspection.") }
                try walk(directory: child, relative: path, content: &content, revision: &revision, cancellable: cancellable)
                try requireIdentity(directory, name: name, expected: DuplicateIdentity(entry))
            } else if type == mode_t(S_IFREG) {
                let file = Darwin.openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard file >= 0 else { throw systemFailure("Open skill file") }
                defer { Darwin.close(file) }
                let initial = try status(file)
                guard DuplicateIdentity(initial) == DuplicateIdentity(entry), initial.st_size >= 0 else { throw failure("A file changed during inspection.") }
                // Finder's per-folder view metadata is not skill content.
                // Only regular .DS_Store files are ignored for equivalence;
                // their identity and timestamps still guard scan-to-apply
                // changes, and the complete original stays in its backup.
                let isSkillContent = name != ".DS_Store"
                if isSkillContent {
                    feed("file", to: &content)
                    feed(path, to: &content)
                    feed(UInt64(initial.st_mode & 0o111), to: &content)
                    feed(UInt64(initial.st_size), to: &content)
                }
                feedRevision(initial, relative: path, to: &revision)
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                var total: Int64 = 0
                while true {
                    if cancellable { try Task.checkCancellation() }
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
                    if count < 0 && errno == EINTR { continue }
                    guard count >= 0 else { throw systemFailure("Read skill file") }
                    if count == 0 { break }
                    total += Int64(count)
                    guard total <= initial.st_size else { throw failure("A file grew during inspection.") }
                    if isSkillContent { content.update(data: Data(buffer.prefix(count))) }
                }
                let final = try status(file)
                guard total == initial.st_size, sameRevision(initial, final),
                      sameRevision(final, try status(at: directory, name: name)) else {
                    throw failure("A file changed during inspection.")
                }
            } else {
                throw failure(type == mode_t(S_IFLNK) ? "Contains a symbolic link: \(path)." : "Contains a special file: \(path).")
            }
        }
        guard sameRevision(before, try status(directory)) else { throw failure("A directory changed during inspection.") }
    }

    private static func feedRevision(_ value: stat, relative: String, to hash: inout SHA256) {
        feed(relative, to: &hash)
        feed(UInt64(bitPattern: Int64(value.st_dev)), to: &hash)
        feed(UInt64(value.st_ino), to: &hash)
        feed(UInt64(value.st_mode), to: &hash)
        feed(UInt64(bitPattern: Int64(value.st_size)), to: &hash)
        feed(UInt64(bitPattern: Int64(value.st_mtimespec.tv_sec)), to: &hash)
        feed(UInt64(bitPattern: Int64(value.st_mtimespec.tv_nsec)), to: &hash)
        // Renaming the root into its backup changes its ctime, but does not edit
        // the tree. Every nested entry retains its full change timestamp.
        if !relative.isEmpty {
            feed(UInt64(bitPattern: Int64(value.st_ctimespec.tv_sec)), to: &hash)
            feed(UInt64(bitPattern: Int64(value.st_ctimespec.tv_nsec)), to: &hash)
        }
    }

    private static func feed(_ value: String, to hash: inout SHA256) {
        let data = Data(value.utf8)
        feed(UInt64(data.count), to: &hash)
        hash.update(data: data)
    }

    private static func feed(_ value: UInt64, to hash: inout SHA256) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { hash.update(data: Data($0)) }
    }

    private static func hex<T: Sequence>(_ bytes: T) -> String where T.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sameRevision(_ left: stat, _ right: stat) -> Bool {
        DuplicateIdentity(left) == DuplicateIdentity(right) && left.st_mode == right.st_mode && left.st_size == right.st_size &&
        left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec && left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec &&
        left.st_ctimespec.tv_sec == right.st_ctimespec.tv_sec && left.st_ctimespec.tv_nsec == right.st_ctimespec.tv_nsec
    }

    private struct BackupRoot {
        let fd: Int32
        let url: URL
        let identity: DuplicateIdentity
    }

    private static func openBackupRoot(_ requested: URL, create: Bool) throws -> BackupRoot {
        guard requested.isFileURL else { throw failure("The backup directory must be local.") }
        let lexical = requested.standardizedFileURL.path
        guard lexical != "/", requested.lastPathComponent != ".", requested.lastPathComponent != ".." else { throw failure("Choose a dedicated backup directory.") }
        // Normalize only macOS's fixed system aliases; user-controlled aliases
        // elsewhere in the backup path are rejected by the no-follow walk.
        let normalized: String
        if lexical == "/var" || lexical.hasPrefix("/var/") { normalized = "/private" + lexical }
        else if lexical == "/tmp" || lexical.hasPrefix("/tmp/") { normalized = "/private" + lexical }
        else { normalized = lexical }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw systemFailure("Open backup path") }
        do {
            for component in normalized.split(separator: "/").map(String.init) {
                var next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT && create {
                    guard Darwin.mkdirat(fd, component, 0o700) == 0 || errno == EEXIST else { throw systemFailure("Create backup directory") }
                    next = Darwin.openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw failure("The backup path is unavailable or contains a symbolic link.") }
                Darwin.close(fd)
                fd = next
            }
            let value = try status(fd)
            guard value.st_uid == geteuid(), value.st_mode & 0o022 == 0 else {
                throw failure("The backup directory must belong to this user and must not be writable by other users.")
            }
            return BackupRoot(fd: fd, url: URL(fileURLWithPath: normalized, isDirectory: true), identity: DuplicateIdentity(value))
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private static func lockRoot(_ directory: Int32) throws -> Int32 {
        let fd = Darwin.openat(directory, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw systemFailure("Open organization lock") }
        do {
            let value = try status(fd)
            guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), value.st_uid == geteuid(), value.st_nlink == 1,
                  value.st_mode & 0o022 == 0 else { throw failure("The organization lock is unsafe.") }
            guard Darwin.lockf(fd, F_TLOCK, 0) == 0 else { throw failure("Another organization is running.") }
            return fd
        } catch { Darwin.close(fd); throw error }
    }

    private static func validateRoot(_ root: BackupRoot) throws {
        guard DuplicateIdentity(try status(root.fd)) == root.identity,
              let identity = SkillFileIdentity.identity(at: root.url), identity.isDirectory,
              identity.inode == ino_t(root.identity.inode),
              UInt64(bitPattern: Int64(identity.device)) == root.identity.device,
              systemPath(root.url.resolvingSymlinksInPath().standardizedFileURL.path) == systemPath(root.url.path) else {
            throw failure("The backup directory changed.")
        }
    }

    private static func openBatch(_ id: String, root: BackupRoot) throws -> Int32 {
        guard UUID(uuidString: id) != nil, !id.contains("/") else { throw failure("Invalid organization record.") }
        try validateRoot(root)
        let fd = Darwin.openat(root.fd, id, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw systemFailure("Open organization backup") }
        return fd
    }

    private static func writeManifest(_ batch: SkillOrganizationBatch, directory: Int32) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(batch)
        guard data.count <= manifestLimit else { throw failure("The organization record is too large.") }
        let name = ".manifest-" + UUID().uuidString
        let fd = Darwin.openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw systemFailure("Create organization record") }
        defer { Darwin.close(fd); _ = Darwin.unlinkat(directory, name, 0) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw systemFailure("Write organization record") }
                offset += count
            }
        }
        guard Darwin.fsync(fd) == 0, Darwin.renameat(directory, name, directory, "manifest.json") == 0,
              Darwin.fsync(directory) == 0 else { throw systemFailure("Save organization record") }
    }

    private static func readManifest(directory: Int32) throws -> SkillOrganizationBatch {
        let fd = Darwin.openat(directory, "manifest.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw systemFailure("Read organization record") }
        defer { Darwin.close(fd) }
        let initial = try status(fd)
        guard initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), initial.st_uid == geteuid(),
              initial.st_nlink == 1, initial.st_size > 0, initial.st_size <= manifestLimit else {
            throw failure("The organization record is unsafe or too large.")
        }
        var data = Data(count: Int(initial.st_size))
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw systemFailure("Read organization record") }
                offset += count
            }
        }
        guard sameRevision(initial, try status(fd)) else { throw failure("The organization record changed while reading.") }
        return try JSONDecoder().decode(SkillOrganizationBatch.self, from: data)
    }

    private static func validateBatch(_ batch: SkillOrganizationBatch, root: URL) throws {
        guard UUID(uuidString: batch.id) != nil, !batch.records.isEmpty else { throw failure("Invalid organization record.") }
        var destinations = Set<String>()
        let batchURL = root.appendingPathComponent(batch.id, isDirectory: true)
        for (index, record) in batch.records.enumerated() {
            guard record.backupPath == batchURL.appendingPathComponent("original-\(index)", isDirectory: true).path,
                  record.copyPath == record.original.path,
                  URL(fileURLWithPath: record.copyPath).deletingLastPathComponent().path == record.original.parentPath,
                  record.copyPath.hasPrefix("/"), record.sourcePath.hasPrefix("/"),
                  !overlap(record.copyPath, record.sourcePath), !overlap(root.path, record.copyPath),
                  !overlap(root.path, record.sourcePath), destinations.insert(record.copyPath).inserted else {
                throw failure("Invalid organization backup paths.")
            }
        }
    }

    private static func preflightRecovery(_ batch: SkillOrganizationBatch, directory: Int32, allowPending: Bool) throws {
        for (index, record) in batch.records.enumerated() {
            let parent = try openParent(record.original)
            defer { Darwin.close(parent) }
            let leaf = URL(fileURLWithPath: record.copyPath).lastPathComponent
            let backup = try optionalStatus(at: directory, name: "original-\(index)")
            let current = try optionalStatus(at: parent, name: leaf)
            if let backup {
                guard DuplicateIdentity(backup) == record.original.identity else { throw failure("A retained original was replaced.") }
                let capture = try inspect(URL(fileURLWithPath: record.backupPath), cancellable: false)
                guard capture.fingerprint == record.original.fingerprint, capture.revision == record.original.revision else {
                    throw failure("A retained original was edited. It was left in the backup directory.")
                }
                if let current { try requireLink(current, parent: parent, name: leaf, record: record) }
                else if !allowPending { throw failure("The installed link is missing; the retained original was left in the backup directory.") }
            } else if allowPending, let current, DuplicateIdentity(current) == record.original.identity {
                // A crash before the move, or after this record was restored.
                let capture = try inspect(URL(fileURLWithPath: record.copyPath), cancellable: false)
                guard capture.fingerprint == record.original.fingerprint, capture.revision == record.original.revision else {
                    throw failure("A pending original changed.")
                }
            } else { throw failure("A retained original is missing.") }
        }
    }

    private static func recover(_ batch: SkillOrganizationBatch, directory: Int32, allowPending: Bool) throws {
        try preflightRecovery(batch, directory: directory, allowPending: allowPending)
        for (index, record) in batch.records.enumerated().reversed() {
            guard try optionalStatus(at: directory, name: "original-\(index)") != nil else { continue }
            try requireIdentity(directory, name: "original-\(index)", expected: record.original.identity)
            let parent = try openParent(record.original)
            defer { Darwin.close(parent) }
            let leaf = URL(fileURLWithPath: record.copyPath).lastPathComponent
            let savedLink = "restoring-\(index)"
            if let current = try optionalStatus(at: parent, name: leaf) {
                try requireLink(current, parent: parent, name: leaf, record: record)
                try renameExclusive(fromFD: parent, name: leaf, toFD: directory, name: savedLink)
                do {
                    try requireLink(try status(at: directory, name: savedLink), parent: directory, name: savedLink, record: record)
                    try renameExclusive(fromFD: directory, name: "original-\(index)", toFD: parent, name: leaf)
                } catch {
                    try? renameExclusive(fromFD: directory, name: savedLink, toFD: parent, name: leaf)
                    throw error
                }
                _ = Darwin.unlinkat(directory, savedLink, 0)
            } else {
                try renameExclusive(fromFD: directory, name: "original-\(index)", toFD: parent, name: leaf)
            }
            _ = Darwin.unlinkat(directory, "link-\(index)", 0)
            guard Darwin.fsync(parent) == 0, Darwin.fsync(directory) == 0 else { throw systemFailure("Save restored skill") }
        }
    }

    private static func requireLink(_ current: stat, parent: Int32, name: String, record: SkillOrganizationRecord) throws {
        guard DuplicateIdentity(current) == record.linkIdentity, current.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) else {
            throw failure("The installed link changed; the skill was left untouched.")
        }
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = buffer.withUnsafeMutableBytes { Darwin.readlinkat(parent, name, $0.baseAddress!.assumingMemoryBound(to: CChar.self), $0.count) }
        guard count >= 0, count < buffer.count, String(bytes: buffer.prefix(count), encoding: .utf8) == record.sourcePath else {
            throw failure("The installed link points to a different original.")
        }
    }

    private static func openParent(_ capture: DuplicateCapture) throws -> Int32 {
        guard URL(fileURLWithPath: capture.parentPath).resolvingSymlinksInPath().standardizedFileURL.path == capture.parentPath else {
            throw failure("A skill parent changed into a symbolic link.")
        }
        let fd = Darwin.open(capture.parentPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw systemFailure("Open skill location") }
        do {
            guard DuplicateIdentity(try status(fd)) == capture.parentIdentity else { throw failure("A skill parent was replaced.") }
            return fd
        } catch { Darwin.close(fd); throw error }
    }

    private static func renameExclusive(fromFD: Int32, name from: String, toFD: Int32, name to: String) throws {
        guard Darwin.renameatx_np(fromFD, from, toFD, to, UInt32(RENAME_EXCL)) == 0 else {
            throw systemFailure("Move skill without overwriting")
        }
    }

    private static func names(in fd: Int32) throws -> [String] {
        let copy = Darwin.dup(fd)
        guard copy >= 0 else { throw systemFailure("List skill directory") }
        guard let stream = Darwin.fdopendir(copy) else { Darwin.close(copy); throw systemFailure("List skill directory") }
        defer { Darwin.closedir(stream) }
        Darwin.rewinddir(stream)
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = Darwin.readdir(stream) else {
                guard errno == 0 else { throw systemFailure("List skill directory") }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(validatingUTF8: $0) }
            }
            guard let name else { throw failure("A filename is not valid UTF-8.") }
            if name != "." && name != ".." { names.append(name) }
        }
        return names.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
    }

    private static func status(_ fd: Int32) throws -> stat {
        var result = stat()
        guard Darwin.fstat(fd, &result) == 0 else { throw systemFailure("Inspect file identity") }
        return result
    }

    private static func optionalStatus(at fd: Int32, name: String) throws -> stat? {
        var result = stat()
        guard Darwin.fstatat(fd, name, &result, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw systemFailure("Inspect directory entry")
        }
        return result
    }

    private static func status(at fd: Int32, name: String) throws -> stat {
        guard let result = try optionalStatus(at: fd, name: name) else { throw failure("A directory entry disappeared.") }
        return result
    }

    private static func requireIdentity(_ fd: Int32, name: String, expected: DuplicateIdentity) throws {
        guard DuplicateIdentity(try status(at: fd, name: name)) == expected else { throw failure("A directory entry changed.") }
    }

    private static func systemPath(_ path: String) -> String {
        if path == "/var" || path.hasPrefix("/var/") { return "/private" + path }
        if path == "/tmp" || path.hasPrefix("/tmp/") { return "/private" + path }
        return path
    }

    private static func overlap(_ first: String, _ second: String) -> Bool {
        let first = systemPath(first), second = systemPath(second)
        return first == second || first.hasPrefix(second + "/") || second.hasPrefix(first + "/")
    }

    private static func failure(_ message: String) -> DuplicateFailure { DuplicateFailure(message: message) }
    private static func systemFailure(_ action: String) -> DuplicateFailure {
        let code = errno
        return failure("\(action): \(String(cString: strerror(code))).")
    }
}
