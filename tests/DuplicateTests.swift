import Foundation
import Darwin

/// Standalone filesystem regressions. Every file is beneath the runner's root;
/// no user skill, Agent configuration, or default home directory is inspected.
@main
struct DuplicateTests {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }
    private actor CancellationGate {
        private var opened = false
        private var pending: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if opened { return }
            await withCheckedContinuation { pending.append($0) }
        }
        func release() {
            opened = true
            for continuation in pending { continuation.resume() }
            pending.removeAll()
        }
    }
    private static var assertions = 0
    private static let fm = FileManager.default

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !condition() { throw Failure(description: message) }
    }

    private static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch { assertions += 1; return }
        throw Failure(description: message)
    }

    private static func fixture(_ root: URL, _ name: String, _ operation: (URL) throws -> Void) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        do { try operation(directory) }
        catch { throw Failure(description: "\(name): \(error)") }
    }

    private static func skill(_ root: URL, _ path: String, content: String = "same", executable: Bool = false) throws -> URL {
        let directory = root.appendingPathComponent(path, isDirectory: true)
        try fm.createDirectory(at: directory.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("---\nname: fixture\ndescription: duplicate test\n---\n\(content)\n".utf8)
            .write(to: directory.appendingPathComponent("SKILL.md"))
        try Data("#!/bin/sh\nprintf '%s' '\(content)'\n".utf8)
            .write(to: directory.appendingPathComponent("scripts/run.sh"))
        try fm.setAttributes([.posixPermissions: executable ? 0o755 : 0o644],
                             ofItemAtPath: directory.appendingPathComponent("scripts/run.sh").path)
        return directory
    }

    private static func candidate(_ path: URL, canReplace: Bool = true, priority: Int = 20,
                                  id: String? = nil) -> SkillDuplicateCandidate {
        SkillDuplicateCandidate(id: id ?? path.path, path: path, name: path.lastPathComponent,
                                location: path.deletingLastPathComponent().lastPathComponent,
                                canReplace: canReplace, sourcePriority: priority)
    }

    private static func isDirectory(_ path: URL) -> Bool {
        SkillFileIdentity.identity(at: path)?.isDirectory == true
    }
    private static func isLink(_ path: URL) -> Bool {
        SkillFileIdentity.identity(at: path)?.isSymbolicLink == true
    }
    private static func text(_ path: URL) throws -> String {
        try String(contentsOf: path, encoding: .utf8)
    }

    private static func onlyGroup(_ scan: SkillDuplicateScan) throws -> SkillDuplicateGroup {
        guard scan.groups.count == 1, let group = scan.groups.first else {
            throw Failure(description: "Expected one duplicate group, found \(scan.groups.count)")
        }
        return group
    }
    private static func updateJournal(_ batch: SkillOrganizationBatch, backupRoot: URL,
                                      _ operation: (inout [String: Any]) throws -> Void) throws {
        let manifest = backupRoot.appendingPathComponent(batch.id).appendingPathComponent("manifest.json")
        guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any] else {
            throw Failure(description: "Organization manifest is not valid JSON")
        }
        try operation(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
    }
    private static func entries(_ group: SkillDuplicateGroup) -> [SkillDuplicatePlanEntry] {
        group.copies.filter { $0.canReplace }.map { SkillDuplicatePlanEntry(source: group.source, copy: $0, fingerprint: group.fingerprint) }
    }

    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw Failure(description: "Missing isolated fixture root") }
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let physicalRoot = root.resolvingSymlinksInPath()
            try run(physicalRoot)
            try await cancellationChecks(physicalRoot)
            print("PASS Duplicates: \(assertions) assertions, complete trees, safe conversion, and reversible backups")
        } catch {
            fputs("FAIL Duplicates: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func cancellationChecks(_ root: URL) async throws {
        let area = root.appendingPathComponent("cancelled-operations", isDirectory: true)
        let source = try skill(area, "Shared/source")
        let copy = try skill(area, "Claude/copy")
        let candidates = [candidate(source, priority: 0), candidate(copy)]
        let group = try onlyGroup(SkillDuplicateService.scan(candidates: candidates))
        let scanGate = CancellationGate()
        let scan = Task.detached {
            await scanGate.wait()
            return try SkillDuplicateService.scan(candidates: candidates)
        }
        scan.cancel()
        await scanGate.release()
        do {
            _ = try await scan.value
            throw Failure(description: "A pre-cancelled scan must stop")
        } catch is CancellationError { assertions += 1 }

        let convertGate = CancellationGate()
        let conversion = Task.detached {
            await convertGate.wait()
            return try SkillDuplicateService.convert(entries: entries(group), backupRoot: area.appendingPathComponent("backups"))
        }
        conversion.cancel()
        await convertGate.release()
        do {
            _ = try await conversion.value
            throw Failure(description: "A pre-cancelled conversion must stop")
        } catch is CancellationError { assertions += 1 }
        try check(isDirectory(source) && isDirectory(copy) && !isLink(copy), "Cancelled operations must retain source and copy as real directories")
    }

    private static func run(_ root: URL) throws {
        try fixture(root, "complete-tree") { area in
            let original = try skill(area, "Codex/original")
            let renamed = try skill(area, "Claude/renamed")
            let differentBody = try skill(area, "Grok/body", content: "else")
            let hidden = try skill(area, "Mirasim/hidden")
            try Data("private resource".utf8).write(to: hidden.appendingPathComponent(".hidden"))
            let nested = try skill(area, "DeepSeek/nested")
            try Data("resource".utf8).write(to: nested.appendingPathComponent("scripts/extra.dat"))
            let executable = try skill(area, "Codex/executable", executable: true)
            let extraDirectory = try skill(area, "Claude/empty-directory")
            try fm.createDirectory(at: extraDirectory.appendingPathComponent("empty"), withIntermediateDirectories: false)
            let scan = try SkillDuplicateService.scan(candidates: [original, renamed, differentBody, hidden, nested, executable, extraDirectory].map { candidate($0) })
            try check(scan.groups.count == 1, "Only byte- and structure-identical trees may form a group")
            let group = try onlyGroup(scan)
            let members = Set(([group.source] + group.copies).map { $0.path.path })
            try check(members == Set([original.path, renamed.path]), "Different folder names may match; body, hidden files, nested assets, executable mode, and empty directories must distinguish trees")
            try check(!group.fingerprint.isEmpty, "Duplicate plans require a reusable complete-tree fingerprint")
            try check(scan.scannedCount == 7, "Every safe candidate must be included in the scan count")
        }

        try fixture(root, "finder-metadata-equality-and-restore") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let absent = try skill(area, "Codex/no-metadata")
            let sourceMetadata = Data([0, 0, 0, 1, 68, 83, 68, 66])
            let copyMetadata = Data([0, 0, 0, 2, 68, 83, 68, 66, 99])
            let nestedMetadata = Data("nested Finder view settings".utf8)
            try sourceMetadata.write(to: source.appendingPathComponent(".DS_Store"))
            try copyMetadata.write(to: copy.appendingPathComponent(".DS_Store"))
            try nestedMetadata.write(to: copy.appendingPathComponent("scripts/.DS_Store"))
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy), candidate(absent)]))
            try check(Set(([group.source] + group.copies).map { $0.path.path }) == Set([source.path, copy.path, absent.path]), "Missing, present, different, and nested regular Finder metadata must not distinguish skill content")
            guard let selected = group.copies.first(where: { $0.path == copy }) else {
                throw Failure(description: "Finder metadata copy missing from duplicate group")
            }
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: [SkillDuplicatePlanEntry(source: group.source, copy: selected, fingerprint: group.fingerprint)], backupRoot: backupRoot)
            let backup = URL(fileURLWithPath: batch.records[0].backupPath)
            try check(try Data(contentsOf: backup.appendingPathComponent(".DS_Store")) == copyMetadata, "Conversion must preserve the copy's exact Finder metadata in its backup")
            try check(try Data(contentsOf: backup.appendingPathComponent("scripts/.DS_Store")) == nestedMetadata, "Conversion must preserve nested Finder metadata in its backup")
            try check(try Data(contentsOf: source.appendingPathComponent(".DS_Store")) == sourceMetadata, "Conversion must leave the original's different Finder metadata unchanged")
            try check(isDirectory(absent) && SkillFileIdentity.identity(at: absent.appendingPathComponent(".DS_Store")) == nil, "Unselected copies must retain their original structure without Finder metadata being added")
            try SkillDuplicateService.restore(batch: batch, backupRoot: backupRoot)
            try check(isDirectory(copy) && !isLink(copy), "Restoring a Finder metadata duplicate must recover its real directory")
            try check(try Data(contentsOf: copy.appendingPathComponent(".DS_Store")) == copyMetadata, "Restore must recover the copy's exact original Finder metadata rather than the source's metadata")
            try check(try Data(contentsOf: copy.appendingPathComponent("scripts/.DS_Store")) == nestedMetadata, "Restore must recover nested Finder metadata bytes")
        }

        for changed in ["source", "copy"] {
            try fixture(root, "stale-finder-metadata-" + changed) { area in
                let source = try skill(area, "Shared/source")
                let copy = try skill(area, "Claude/copy")
                try Data([1, 2, 3, 4]).write(to: source.appendingPathComponent(".DS_Store"))
                try Data([4, 3, 2, 1]).write(to: copy.appendingPathComponent(".DS_Store"))
                let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
                let target = (changed == "source" ? source : copy).appendingPathComponent(".DS_Store")
                let newerMetadata = Data([9, 8, 7, 6])
                try newerMetadata.write(to: target)
                try rejects("A Finder metadata revision change after scanning must still invalidate the plan") {
                    _ = try SkillDuplicateService.convert(entries: entries(group), backupRoot: area.appendingPathComponent("backups"))
                }
                try check(isDirectory(source) && isDirectory(copy) && !isLink(copy), "A stale Finder metadata plan must preserve real source and copy directories")
                try check(try Data(contentsOf: target) == newerMetadata, "A refused conversion must preserve Finder metadata edited after the scan")
            }
        }

        try fixture(root, "unsafe-finder-metadata") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let linked = try skill(area, "unsafe/linked")
            let fifo = try skill(area, "unsafe/fifo")
            let directory = try skill(area, "other/directory-metadata")
            try Data([1, 2, 3]).write(to: copy.appendingPathComponent(".DS_Store"))
            try fm.createSymbolicLink(at: linked.appendingPathComponent(".DS_Store"), withDestinationURL: source.appendingPathComponent("SKILL.md"))
            try check(Darwin.mkfifo(fifo.appendingPathComponent(".DS_Store").path, mode_t(0o600)) == 0, "Could not create isolated Finder metadata FIFO fixture")
            try fm.createDirectory(at: directory.appendingPathComponent(".DS_Store"), withIntermediateDirectories: false)
            let started = ProcessInfo.processInfo.systemUptime
            let scan = try SkillDuplicateService.scan(candidates: [source, copy, linked, fifo, directory].map { candidate($0) })
            let group = try onlyGroup(scan)
            try check(Set(([group.source] + group.copies).map { $0.path.path }) == Set([source.path, copy.path]), "Only regular Finder metadata files may be ignored; directories with that name remain structural content")
            try check(scan.skipped.contains { $0.path == linked } && scan.skipped.contains { $0.path == fifo }, "A symbolic link or special file named .DS_Store must make the tree unsafe rather than being ignored")
            try check(ProcessInfo.processInfo.systemUptime - started < 2, "Finder metadata special files must not block scanning")
        }

        try fixture(root, "source-choice") { area in
            let shared = try skill(area, "Shared/skill")
            let library = try skill(area, "Library/skill")
            let agent = try skill(area, "Agent/skill")
            let other = try skill(area, "ZAgent/skill")
            let scan = try SkillDuplicateService.scan(candidates: [
                candidate(agent, priority: 20), candidate(library, priority: 10),
                candidate(shared, canReplace: false, priority: 0), candidate(other, priority: 20)
            ])
            let group = try onlyGroup(scan)
            try check(group.source.path == shared, "An existing global original must be preferred even when protected")
            try check(group.source.canReplace == false && group.copies.allSatisfy { $0.canReplace }, "A protected global entry must remain the original")
            let localScan = try SkillDuplicateService.scan(candidates: [candidate(other), candidate(agent)])
            try check(try onlyGroup(localScan).source.path == agent, "Agent-only copies must retain a deterministic existing original")
            let reverse = try SkillDuplicateService.scan(candidates: [candidate(agent), candidate(other)])
            try check(try onlyGroup(reverse).source.path == agent, "Input order must not change the chosen original")
        }

        try fixture(root, "aliases-and-unsafe-trees") { area in
            let original = try skill(area, "real/original")
            let alias = area.appendingPathComponent("alias")
            try fm.createSymbolicLink(at: alias, withDestinationURL: original)
            let aliasParent = area.appendingPathComponent("aliased-parent")
            try fm.createSymbolicLink(at: aliasParent, withDestinationURL: original.deletingLastPathComponent())
            let parentAliasEntry = aliasParent.appendingPathComponent(original.lastPathComponent)
            let linkedFile = try skill(area, "unsafe/linked-file")
            try fm.createSymbolicLink(at: linkedFile.appendingPathComponent("resource-link"), withDestinationURL: original.appendingPathComponent("SKILL.md"))
            let linkedDirectory = try skill(area, "unsafe/linked-dir")
            try fm.createSymbolicLink(at: linkedDirectory.appendingPathComponent("linked-scripts"), withDestinationURL: original.appendingPathComponent("scripts"))
            let special = try skill(area, "unsafe/fifo")
            try check(Darwin.mkfifo(special.appendingPathComponent("pipe").path, mode_t(0o600)) == 0, "Could not create isolated FIFO fixture")
            let started = ProcessInfo.processInfo.systemUptime
            let scan = try SkillDuplicateService.scan(candidates: [original, alias, parentAliasEntry, linkedFile, linkedDirectory, special].map { candidate($0) })
            try check(scan.groups.isEmpty, "Aliases to one physical directory are not independent duplicate copies")
            for unsafe in [linkedFile, linkedDirectory, special] {
                try check(scan.skipped.contains { $0.path.path == unsafe.path }, "Unsafe trees must be reported rather than followed: \(unsafe.lastPathComponent)")
            }
            try check(ProcessInfo.processInfo.systemUptime - started < 2, "Scanning a FIFO must not block")
        }

        try fixture(root, "convert-and-restore") { area in
            let source = try skill(area, "Shared/skill", executable: true)
            let copy = try skill(area, "Claude/renamed", executable: true)
            let originalIdentity = SkillFileIdentity.identity(at: source)
            let originalDefinition = try Data(contentsOf: source.appendingPathComponent("SKILL.md"))
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(copy), candidate(source, canReplace: false, priority: 0)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            try check(batch.records.count == 1 && batch.records[0].sourcePath == source.path && batch.records[0].copyPath == copy.path, "A batch must record the exact retained source and replaced copy")
            try check(isDirectory(source) && SkillFileIdentity.identity(at: source) == originalIdentity, "Converting a duplicate must retain the original directory entry")
            try check(isLink(copy), "The duplicate must become a symbolic link")
            try check(copy.resolvingSymlinksInPath() == source, "The new link must resolve to the chosen original")
            try check(try text(copy.appendingPathComponent("scripts/run.sh")) == text(source.appendingPathComponent("scripts/run.sh")), "Linked assets must remain readable")
            let backup = URL(fileURLWithPath: batch.records[0].backupPath, isDirectory: true)
            try check(isDirectory(backup) && !isLink(backup), "The original copy must remain a real backup directory")
            try check(try text(backup.appendingPathComponent("SKILL.md")) == text(source.appendingPathComponent("SKILL.md")), "The backup must preserve complete content")
            let backupMode = try fm.attributesOfItem(atPath: backup.appendingPathComponent("scripts/run.sh").path)[.posixPermissions] as? NSNumber
            try check(backupMode?.intValue == 0o755, "Conversion backups must preserve executable permissions")
            let loaded = try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot)
            try check(loaded?.id == batch.id, "The latest batch must be recoverable after reopening the app")
            guard let loaded else { throw Failure(description: "Persisted organization missing") }
            let newerSource = Data("new source work after organizing".utf8)
            try newerSource.write(to: source.appendingPathComponent("SKILL.md"))
            try SkillDuplicateService.restore(batch: loaded, backupRoot: backupRoot)
            try check(isDirectory(copy) && !isLink(copy), "Restoring must recover the copy as a real directory")
            try check(try Data(contentsOf: copy.appendingPathComponent("SKILL.md")) == originalDefinition, "Restoring must recover the original copy even after its shared source is edited")
            try check(try Data(contentsOf: source.appendingPathComponent("SKILL.md")) == newerSource, "Restoring a backup must preserve newer source content")
            try check(SkillFileIdentity.identity(at: source) == originalIdentity, "Restoring must leave the retained source entry untouched")
            try check(try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot) == nil, "A restored batch must no longer be offered for undo")
            try rejects("A restored batch must not be replayed") {
                try SkillDuplicateService.restore(batch: loaded, backupRoot: backupRoot)
            }
        }

        for changed in ["source", "copy"] {
            try fixture(root, "stale-content-" + changed) { area in
                let source = try skill(area, "Shared/source")
                let copy = try skill(area, "Claude/copy")
                let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
                let target = (changed == "source" ? source : copy).appendingPathComponent("scripts/run.sh")
                let originalData = try Data(contentsOf: target)
                var edited = originalData
                edited[edited.count - 2] ^= 1
                try edited.write(to: target)
                try rejects("Changing \(changed) content after scanning must reject conversion") {
                    _ = try SkillDuplicateService.convert(entries: entries(group), backupRoot: area.appendingPathComponent("backups"))
                }
                try check(isDirectory(source) && isDirectory(copy) && !isLink(copy), "A stale plan must not replace either directory")
                try check(try Data(contentsOf: target) == edited, "Rejecting a stale plan must preserve the user's newer edit")
            }
        }

        try fixture(root, "stale-entry-identity") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let oldCopy = area.appendingPathComponent("old-copy")
            try fm.moveItem(at: copy, to: oldCopy)
            try fm.copyItem(at: oldCopy, to: copy)
            try rejects("Replacing a scanned folder with a new identical entry must invalidate the plan") {
                _ = try SkillDuplicateService.convert(entries: entries(group), backupRoot: area.appendingPathComponent("backups"))
            }
            try check(isDirectory(copy) && isDirectory(oldCopy), "A rejected identity change must preserve both folders")
        }

        try fixture(root, "atomic-preflight") { area in
            let source = try skill(area, "Shared/source")
            let first = try skill(area, "Claude/first")
            let second = try skill(area, "Codex/second")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(first), candidate(second)]))
            try Data("changed".utf8).write(to: second.appendingPathComponent("new-file"))
            try rejects("One stale destination must reject an entire batch") {
                _ = try SkillDuplicateService.convert(entries: entries(group), backupRoot: area.appendingPathComponent("backups"))
            }
            try check(isDirectory(first) && isDirectory(second) && !isLink(first) && !isLink(second), "Batch preflight must leave every copy intact when any copy changed")
        }

        try fixture(root, "original-never-destination") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let invalid = SkillDuplicatePlanEntry(source: group.source, copy: group.source, fingerprint: group.fingerprint)
            try rejects("The chosen original cannot also be a replacement destination") {
                _ = try SkillDuplicateService.convert(entries: [invalid], backupRoot: area.appendingPathComponent("backups"))
            }
            try check(isDirectory(source) && isDirectory(copy), "A malformed plan must leave both original and copy intact")
        }

        try fixture(root, "cross-source-plan") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let third = try skill(area, "Codex/third")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy), candidate(third)]))
            guard let copyCandidate = group.copies.first(where: { $0.path == copy }),
                  let thirdCandidate = group.copies.first(where: { $0.path == third }) else {
                throw Failure(description: "Cross-source fixture candidates missing")
            }
            let inconsistent = [
                SkillDuplicatePlanEntry(source: group.source, copy: copyCandidate, fingerprint: group.fingerprint),
                SkillDuplicatePlanEntry(source: copyCandidate, copy: thirdCandidate, fingerprint: group.fingerprint)
            ]
            try rejects("A retained source of any entry must never be replaced by another entry") {
                _ = try SkillDuplicateService.convert(entries: inconsistent, backupRoot: area.appendingPathComponent("backups"))
            }
            try check(isDirectory(source) && isDirectory(copy) && isDirectory(third), "Rejecting conflicting plan roles must preserve every original entry")
        }

        try fixture(root, "protected-copy") { area in
            let source = try skill(area, "Shared/source")
            let protected = try skill(area, "Builtin/copy")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(protected, canReplace: false), candidate(copy)]))
            let protectedCandidate = candidate(protected, canReplace: false)
            let invalid = SkillDuplicatePlanEntry(source: group.source, copy: protectedCandidate, fingerprint: group.fingerprint)
            try rejects("A protected original cannot be converted as a destination") {
                _ = try SkillDuplicateService.convert(entries: [invalid], backupRoot: area.appendingPathComponent("backups"))
            }
            try check(isDirectory(protected), "Refusing a protected destination must retain its directory")
        }

        try fixture(root, "restore-conflict") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let differentSource = try skill(area, "Other/source", content: "new user selection")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            try fm.removeItem(at: copy)
            try fm.createSymbolicLink(at: copy, withDestinationURL: differentSource)
            try rejects("Undo must refuse to overwrite a subsequently changed link") {
                try SkillDuplicateService.restore(batch: batch, backupRoot: backupRoot)
            }
            try check(isLink(copy) && copy.resolvingSymlinksInPath() == differentSource, "Conflicted undo must retain the user's current link")
            try check(isDirectory(URL(fileURLWithPath: batch.records[0].backupPath)), "A conflicted undo must retain its recoverable backup")
            try check(isDirectory(source), "Conflicted undo must not alter the original")
        }

        try fixture(root, "restore-directory-conflict") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            try fm.removeItem(at: copy)
            _ = try skill(area, "Claude/copy", content: "new work")
            try rejects("Undo must refuse to overwrite a directory created after conversion") {
                try SkillDuplicateService.restore(batch: batch, backupRoot: backupRoot)
            }
            try check(isDirectory(copy) && (try text(copy.appendingPathComponent("SKILL.md"))).contains("new work"), "Conflicted undo must retain newer independent content")
        }

        try fixture(root, "missing-installed-link") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            try fm.removeItem(at: copy)
            try rejects("A completed conversion must treat a subsequently removed link as a user conflict") {
                try SkillDuplicateService.restore(batch: batch, backupRoot: backupRoot)
            }
            try check(SkillFileIdentity.identity(at: copy) == nil && isDirectory(URL(fileURLWithPath: batch.records[0].backupPath)), "Undo must retain a user's deliberate deletion and keep its backup")
        }

        try fixture(root, "interrupted-install") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            // Recreate a crash after retaining the copy but before installing its link.
            try updateJournal(batch, backupRoot: backupRoot) { $0["completed"] = false }
            try fm.removeItem(at: copy)
            guard let pending = try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot) else {
                throw Failure(description: "Interrupted installation must remain recoverable")
            }
            try SkillDuplicateService.restore(batch: pending, backupRoot: backupRoot)
            try check(isDirectory(copy) && !isLink(copy), "Restart recovery must restore a retained original whose link was never installed")
            try check(try Data(contentsOf: copy.appendingPathComponent("SKILL.md")) == Data(contentsOf: source.appendingPathComponent("SKILL.md")), "Interrupted installation recovery must retain original content")
            try check(try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot) == nil, "Recovered installation must no longer be offered for undo")
        }

        try fixture(root, "interrupted-undo") { area in
            let source = try skill(area, "Shared/source")
            let first = try skill(area, "Claude/first")
            let second = try skill(area, "Codex/second")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(first), candidate(second)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            try updateJournal(batch, backupRoot: backupRoot) { $0["restoring"] = true }
            // Recreate a crash after one undo entry was restored and another remains linked.
            let alreadyRestored = batch.records[0]
            try fm.removeItem(atPath: alreadyRestored.copyPath)
            try fm.moveItem(atPath: alreadyRestored.backupPath, toPath: alreadyRestored.copyPath)
            let restoredIdentity = SkillFileIdentity.identity(at: URL(fileURLWithPath: alreadyRestored.copyPath))
            guard let pending = try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot) else {
                throw Failure(description: "Interrupted undo must remain recoverable")
            }
            try SkillDuplicateService.restore(batch: pending, backupRoot: backupRoot)
            try check(isDirectory(first) && isDirectory(second) && !isLink(first) && !isLink(second), "Restart must finish remaining undo records after earlier records were restored")
            try check(SkillFileIdentity.identity(at: URL(fileURLWithPath: alreadyRestored.copyPath)) == restoredIdentity, "Resuming undo must retain an already restored directory entry")
            try check(try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot) == nil, "A resumed undo must finish its persistent journal")
        }

        try fixture(root, "invalid-staging-history") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            let pending = backupRoot.appendingPathComponent(UUID().uuidString.lowercased())
            try fm.createDirectory(at: pending, withIntermediateDirectories: false)
            try check(try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot)?.id == batch.id, "An interrupted staging directory without a journal must not hide valid recovery history")
            let corrupt = backupRoot.appendingPathComponent(UUID().uuidString.lowercased())
            try fm.createDirectory(at: corrupt, withIntermediateDirectories: false)
            try Data("invalid journal".utf8).write(to: corrupt.appendingPathComponent("manifest.json"))
            try check(try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot)?.id == batch.id, "An invalid staging journal must not hide valid recovery history")
            let outside = area.appendingPathComponent("outside")
            try fm.createDirectory(at: outside, withIntermediateDirectories: false)
            try fm.createSymbolicLink(at: backupRoot.appendingPathComponent(UUID().uuidString.lowercased()), withDestinationURL: outside)
            try Data("not a directory".utf8).write(to: backupRoot.appendingPathComponent(UUID().uuidString.lowercased()))
            try check(try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot)?.id == batch.id, "UUID-named files and symlinks must be ignored without following or blocking valid recovery")

            let manifest = backupRoot.appendingPathComponent(batch.id).appendingPathComponent("manifest.json")
            let misplaced = backupRoot.appendingPathComponent(UUID().uuidString.lowercased())
            let forgedID = UUID().uuidString.lowercased()
            try fm.createDirectory(at: misplaced, withIntermediateDirectories: false)
            guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
                  var records = json["records"] as? [[String: Any]] else {
                throw Failure(description: "Organization manifest is not valid JSON")
            }
            json["id"] = forgedID
            json["createdAt"] = (json["createdAt"] as? Double ?? 0) + 3600
            records[0]["backupPath"] = batch.records[0].backupPath.replacingOccurrences(of: batch.id, with: forgedID)
            json["records"] = records
            try JSONSerialization.data(withJSONObject: json).write(to: misplaced.appendingPathComponent("manifest.json"))
            try check(try SkillDuplicateService.loadLastBatch(backupRoot: backupRoot)?.id == batch.id, "A journal whose batch ID differs from its containing directory must be ignored")
            try check(isLink(copy) && isDirectory(URL(fileURLWithPath: batch.records[0].backupPath)), "Inspecting invalid recovery entries must preserve real skills and backups")
        }

        try fixture(root, "edited-backup") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            let backup = URL(fileURLWithPath: batch.records[0].backupPath)
            let edited = Data("user edit inside retained backup".utf8)
            try edited.write(to: backup.appendingPathComponent("SKILL.md"))
            try rejects("Undo must refuse a retained backup that was edited after conversion") {
                try SkillDuplicateService.restore(batch: batch, backupRoot: backupRoot)
            }
            try check(isLink(copy) && copy.resolvingSymlinksInPath() == source, "An edited backup must not replace the current working link")
            try check(try Data(contentsOf: backup.appendingPathComponent("SKILL.md")) == edited, "Refusing an edited backup must preserve its user's edits")
        }

        try fixture(root, "tampered-journal") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let outside = try skill(area, "outside/untouched", content: "untouched")
            let outsideIdentity = SkillFileIdentity.identity(at: outside)
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            let manifest = backupRoot.appendingPathComponent(batch.id).appendingPathComponent("manifest.json")
            guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
                  var records = json["records"] as? [[String: Any]] else {
                throw Failure(description: "Organization manifest is not valid JSON")
            }
            records[0]["backupPath"] = outside.path
            json["records"] = records
            try JSONSerialization.data(withJSONObject: json).write(to: manifest)
            try rejects("A journal cannot redirect restore outside its own backup batch") {
                try SkillDuplicateService.restore(batch: batch, backupRoot: backupRoot)
            }
            try check(SkillFileIdentity.identity(at: outside) == outsideIdentity && isDirectory(outside), "Tampered recovery paths must not move unrelated directories")
            try check(isLink(copy) && isDirectory(URL(fileURLWithPath: batch.records[0].backupPath)), "Invalid journals must preserve the current link and real retained backup")
        }

        try fixture(root, "replaced-backup-root") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let backupRoot = area.appendingPathComponent("backups")
            let movedRoot = area.appendingPathComponent("moved-backups")
            let batch = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
            try fm.moveItem(at: backupRoot, to: movedRoot)
            try fm.createSymbolicLink(at: backupRoot, withDestinationURL: movedRoot)
            try rejects("Recovery must refuse a backup root replaced by a symbolic link") {
                try SkillDuplicateService.restore(batch: batch, backupRoot: backupRoot)
            }
            try check(isLink(copy) && copy.resolvingSymlinksInPath() == source, "Refusing substituted backup storage must retain the installed link")
            try check(isDirectory(movedRoot.appendingPathComponent(batch.id).appendingPathComponent("original-0")), "Substituted backup storage must retain its original copy")
        }

        try fixture(root, "backup-root-links") { area in
            let source = try skill(area, "Shared/source")
            let copy = try skill(area, "Claude/copy")
            let group = try onlyGroup(SkillDuplicateService.scan(candidates: [candidate(source, priority: 0), candidate(copy)]))
            let realBackups = area.appendingPathComponent("real-backups")
            try fm.createDirectory(at: realBackups, withIntermediateDirectories: false)
            let alias = area.appendingPathComponent("backup-alias")
            try fm.createSymbolicLink(at: alias, withDestinationURL: realBackups)
            for backupRoot in [alias, alias.appendingPathComponent("nested")] {
                try rejects("A symlinked backup root or ancestor must be refused") {
                    _ = try SkillDuplicateService.convert(entries: entries(group), backupRoot: backupRoot)
                }
            }
            try check(try fm.contentsOfDirectory(atPath: realBackups.path).isEmpty, "Refused backup roots must not receive files")
            try check(isDirectory(source) && isDirectory(copy), "Unsafe backup storage must prevent any conversion")
        }

    }
}
