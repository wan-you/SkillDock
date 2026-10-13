import Foundation

// App code and this file are combined by run-security-tests.sh, allowing the
// regression cases to exercise the actual private Store methods. Every home
// lookup in that build is redirected here, and application discovery is empty.
var securityTestHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SKILLDOCK_TEST_HOME"]!, isDirectory: true)
private let securityTestRoot = securityTestHome
private var checkedAssertions = 0

private struct SecurityTestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    checkedAssertions += 1
    guard condition() else { throw SecurityTestFailure(description: message) }
}

private func exists(_ path: URL) -> Bool {
    FileManager.default.fileExists(atPath: path.path)
}

private func makeSkill(_ path: URL, marker: String = "original") throws {
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    try "---\nname: \(path.lastPathComponent)\ndescription: fixture\n---\n".write(to: path.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    try marker.write(to: path.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
}

@MainActor
private func skill(_ store: SkillStore, at path: URL) throws -> SkillItem {
    let expected = path.standardizedFileURL.path
    guard let found = store.skills.first(where: { $0.id == expected }) else {
        throw SecurityTestFailure(description: "Fixture skill was not scanned: \(expected); found \(store.skills.map(\.id))")
    }
    return found
}

@MainActor
private func fixture(_ name: String, setup: (URL) throws -> Void = { _ in }, _ body: (SkillStore) throws -> Void) throws {
    securityTestHome = securityTestRoot.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: securityTestHome, withIntermediateDirectories: true)
    try setup(securityTestHome)
    let suite = "SkillDock.SecurityTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SkillStore(defaults: defaults)
    try body(store)
}

@main
private struct SecurityTests {
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        try fixture("ordinary-startup") { store in
            try check(exists(store.libraryDirectory), "An ordinary first launch must create Library")
        }

        try fixture("readonly-startup-alias", setup: { home in
            let shared = home.appendingPathComponent(".agents/skills", isDirectory: true)
            let libraryParent = home.appendingPathComponent("Library/Application Support/SkillDock", isDirectory: true)
            try fm.createDirectory(at: shared, withIntermediateDirectories: true)
            try fm.createDirectory(at: libraryParent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: libraryParent, withDestinationURL: shared)
            try "preserve".write(to: shared.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
            try check(!exists(shared.appendingPathComponent("Library")), "Startup alias fixture must not contain Library beforehand")
        }) { store in
            try check(!exists(store.sharedDirectory.appendingPathComponent("Library")), "First launch must not create Library inside a protected Shared ancestor alias")
            try check(!exists(store.libraryDirectory), "A read-only startup Library alias must not be initialized")
            try check((try? String(contentsOf: store.sharedDirectory.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "preserve", "Startup must preserve the existing Shared contents")
        }

        try fixture("normal-link") { store in
            let source = store.sharedDirectory.appendingPathComponent("shared-link-source", isDirectory: true)
            let link = AgentKind.claude.skillDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try makeSkill(source)
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            store.refresh()
            let protectedSource = try skill(store, at: source)
            try check(!store.canDelete(protectedSource) && !store.canArchive(protectedSource), "Shared sources must remain read-only")
            let leaf = try skill(store, at: link)
            try check(leaf.isSymbolicLink && store.canDelete(leaf), "A current leaf link must be removable")
            try check(!store.canArchive(leaf), "A leaf link must not be archived as its source")
            store.delete(leaf)
            try check(SkillFileIdentity.identity(at: link) == nil && exists(source.appendingPathComponent("sentinel.txt")), "Removing a Shared leaf link must retain its source")
        }

        try fixture("replaced-link") { store in
            let source = securityTestHome.appendingPathComponent("outside/source", isDirectory: true)
            let link = AgentKind.codex.skillDirectory.appendingPathComponent("replaced", isDirectory: true)
            try makeSkill(source)
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            store.refresh()
            let cached = try skill(store, at: link)
            try fm.removeItem(at: link)
            try makeSkill(link, marker: "replacement")
            try check(!store.canDelete(cached), "A stale leaf link must not authorize deleting its replacement")
            store.delete(cached)
            store.archive(cached)
            store.transfer(cached, to: .claude, mode: .copy)
            store.copyToLibrary(cached)
            try check(exists(link.appendingPathComponent("sentinel.txt")) && exists(source), "Stale link operations must preserve both directories")
            try check(!exists(AgentKind.claude.skillDirectory.appendingPathComponent("replaced")) && !exists(store.libraryDirectory.appendingPathComponent("replaced")), "Transfers must reject a stale source")
        }

        try fixture("replaced-directory") { store in
            let path = AgentKind.codex.skillDirectory.appendingPathComponent("same-type", isDirectory: true)
            let original = securityTestHome.appendingPathComponent("retained-original", isDirectory: true)
            try makeSkill(path)
            store.refresh()
            let cached = try skill(store, at: path)
            try fm.moveItem(at: path, to: original)
            try makeSkill(path, marker: "replacement")
            try check(!store.canDelete(cached) && !store.canArchive(cached), "Changed directory identity must invalidate cached operations")
            store.delete(cached)
            store.archive(cached)
            try check(exists(path) && exists(original), "Same-type replacements must survive stale operations")
        }

        try fixture("redirected-root") { store in
            let root = AgentKind.codex.skillDirectory
            let local = root.appendingPathComponent("retargeted", isDirectory: true)
            let shared = store.sharedDirectory.appendingPathComponent(local.lastPathComponent, isDirectory: true)
            let saved = securityTestHome.appendingPathComponent("original-root", isDirectory: true)
            try makeSkill(local)
            try makeSkill(shared)
            store.refresh()
            let cached = try skill(store, at: local)
            try fm.moveItem(at: root, to: saved)
            try fm.createSymbolicLink(at: root, withDestinationURL: store.sharedDirectory)
            try check(!store.canDelete(cached) && !store.canArchive(cached), "A retargeted Agent root must invalidate its cached children")
            store.delete(cached)
            store.archive(cached)
            try check(exists(shared) && exists(saved.appendingPathComponent(local.lastPathComponent)), "A redirected root must not delete or move Shared")
        }

        try fixture("nested-containers") { store in
            let nested = store.dotAgentPath.appendingPathComponent("skills", isDirectory: true)
            let synced = AgentKind.claude.skillDirectory.appendingPathComponent("synced", isDirectory: true)
            for container in [nested, synced] {
                try makeSkill(container)
                try makeSkill(container.appendingPathComponent("child", isDirectory: true))
            }
            store.refresh()
            for container in [nested, synced] {
                let item = try skill(store, at: container)
                try check(!store.canDelete(item) && !store.canArchive(item), "A skills container must never be managed as a leaf skill")
                store.delete(item)
                store.archive(item)
                try check(exists(container.appendingPathComponent("child/sentinel.txt")), "All skills in a protected container must remain present")
            }
        }

        try fixture("ordinary-management") { store in
            let source = AgentKind.codex.skillDirectory.appendingPathComponent("ordinary", isDirectory: true)
            try makeSkill(source)
            store.refresh()
            let original = try skill(store, at: source)
            try check(store.canArchive(original) && store.canDelete(original), "An ordinary local skill must remain manageable")
            // Editing its definition changes neither inode nor parent identity.
            try "---\nname: edited\n---\n".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            try check(store.canArchive(original), "An ordinary definition edit must not invalidate the directory snapshot")
            store.copyToLibrary(original)
            let copy = store.libraryDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try check(exists(source) && exists(copy), "Copying to Library must retain the original")
            try check(SkillFileIdentity.identity(at: source) != SkillFileIdentity.identity(at: copy), "A directory copy must be independent")
            let librarySkill = try skill(store, at: copy)
            store.transfer(librarySkill, to: .claude, mode: .link)
            let agentLink = AgentKind.claude.skillDirectory.appendingPathComponent(copy.lastPathComponent, isDirectory: true)
            try check(SkillFileIdentity.identity(at: agentLink)?.isSymbolicLink == true, "A normal transfer must create a leaf link")
            store.delete(try skill(store, at: agentLink))
            try check(exists(copy), "Deleting the transferred link must retain Library")
            store.archive(try skill(store, at: source))
            let archived = store.archivedDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try check(!exists(source) && exists(archived), "Archiving an ordinary directory must move it")
            let archivedSkill = try skill(store, at: archived)
            try check(store.canDelete(archivedSkill) && !store.canArchive(archivedSkill), "An archived skill may be deleted but not rearchived")
            store.delete(archivedSkill)
            try check(!exists(archived) && exists(copy), "Deleting an archive must preserve the independent copy")
        }

        try fixture("custom-destination-alias") { store in
            let source = store.libraryDirectory.appendingPathComponent("custom-link", isDirectory: true)
            let customRoot = securityTestHome.appendingPathComponent("custom-storage/skills", isDirectory: true)
            let agentRoot = AgentKind.claude.skillDirectory
            try makeSkill(source)
            try fm.createDirectory(at: customRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: agentRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: agentRoot, withDestinationURL: customRoot)
            store.refresh()
            store.transfer(try skill(store, at: source), to: .claude, mode: .link)
            try check(SkillFileIdentity.identity(at: customRoot.appendingPathComponent(source.lastPathComponent))?.isSymbolicLink == true, "A custom destination alias outside protected sources must remain writable")
            try check(exists(source), "A custom-root transfer must preserve its source")
        }

        try fixture("readonly-transfer") { store in
            let source = store.libraryDirectory.appendingPathComponent("readonly-target", isDirectory: true)
            let destination = AgentKind.claude.skillDirectory
            try makeSkill(source)
            try fm.createDirectory(at: store.sharedDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: destination, withDestinationURL: store.sharedDirectory)
            store.refresh()
            store.transfer(try skill(store, at: source), to: .claude, mode: .copy)
            try check(!exists(store.sharedDirectory.appendingPathComponent(source.lastPathComponent)), "An Agent destination alias must not write into Shared")
        }

        try fixture("readonly-transfer-missing-root") { store in
            let source = store.libraryDirectory.appendingPathComponent("missing-root-target", isDirectory: true)
            let destinationParent = AgentKind.claude.skillDirectory.deletingLastPathComponent()
            try makeSkill(source)
            try fm.createDirectory(at: store.sharedDirectory, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: destinationParent, withDestinationURL: store.sharedDirectory)
            store.refresh()
            store.transfer(try skill(store, at: source), to: .claude, mode: .copy)
            try check(!exists(store.sharedDirectory.appendingPathComponent("skills")), "A destination with a protected ancestor alias must be rejected before creating missing directories")
        }

        try fixture("readonly-library") { store in
            let source = AgentKind.claude.skillDirectory.appendingPathComponent("readonly-library", isDirectory: true)
            try makeSkill(source)
            try fm.createDirectory(at: store.sharedDirectory, withIntermediateDirectories: true)
            store.refresh()
            let cached = try skill(store, at: source)
            try fm.removeItem(at: store.libraryDirectory)
            try fm.createSymbolicLink(at: store.libraryDirectory, withDestinationURL: store.sharedDirectory)
            store.copyToLibrary(cached)
            try check(exists(source) && !exists(store.sharedDirectory.appendingPathComponent(source.lastPathComponent)), "A Library root alias must not write into Shared")
        }

        try fixture("readonly-archive") { store in
            let source = AgentKind.claude.skillDirectory.appendingPathComponent("readonly-archive", isDirectory: true)
            try makeSkill(source)
            try fm.createDirectory(at: store.sharedDirectory, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: store.archivedDirectory, withDestinationURL: store.sharedDirectory)
            store.refresh()
            store.archive(try skill(store, at: source))
            try check(exists(source) && !exists(store.sharedDirectory.appendingPathComponent(source.lastPathComponent)), "An archive alias must not move skills into Shared")
        }

        try fixture("readonly-synced-destination") { store in
            let source = store.libraryDirectory.appendingPathComponent("synced-destination", isDirectory: true)
            let destination = AgentKind.codex.skillDirectory
            let synced = AgentKind.claude.skillDirectory.appendingPathComponent("synced", isDirectory: true)
            try makeSkill(source)
            try fm.createDirectory(at: synced, withIntermediateDirectories: true)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: destination, withDestinationURL: synced)
            store.refresh()
            store.transfer(try skill(store, at: source), to: .codex, mode: .copy)
            try check(!exists(synced.appendingPathComponent(source.lastPathComponent)), "An Agent alias must not write into Claude synced")
        }

        try fixture("readonly-default-destination") { store in
            let source = store.libraryDirectory.appendingPathComponent("default-destination", isDirectory: true)
            let defaultRoot = AgentKind.codex.skillDirectory.appendingPathComponent(".system", isDirectory: true)
            let destination = AgentKind.claude.skillDirectory
            try makeSkill(source)
            try fm.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: destination, withDestinationURL: defaultRoot)
            store.refresh()
            store.transfer(try skill(store, at: source), to: .claude, mode: .copy)
            try check(!exists(defaultRoot.appendingPathComponent(source.lastPathComponent)), "An Agent alias must not write into a default-skill source")
        }

        try fixture("readonly-claude-cache-destination") { store in
            let source = store.libraryDirectory.appendingPathComponent("claude-cache-destination", isDirectory: true)
            let cacheRoot = securityTestHome.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/generated-cache/skills", isDirectory: true)
            let destination = AgentKind.codex.skillDirectory
            try makeSkill(source)
            try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: destination, withDestinationURL: cacheRoot)
            store.refresh()
            store.transfer(try skill(store, at: source), to: .codex, mode: .copy)
            try check(!exists(cacheRoot.appendingPathComponent(source.lastPathComponent)), "An Agent alias must not write into a Claude-generated cache without a manifest")
        }

        try fixture("dangling-collision") { store in
            let source = store.libraryDirectory.appendingPathComponent("collision", isDirectory: true)
            let destination = AgentKind.claude.skillDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            let missing = securityTestHome.appendingPathComponent("missing-source", isDirectory: true)
            try makeSkill(source)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: destination, withDestinationURL: missing)
            store.refresh()
            store.transfer(try skill(store, at: source), to: .claude, mode: .copy)
            try check((try? fm.destinationOfSymbolicLink(atPath: destination.path)) == missing.path, "A dangling destination link must not be replaced")
            try check(exists(source), "A collision must preserve the source")
        }

        print("Store security regressions passed (\(checkedAssertions) assertions).")
    }
}
