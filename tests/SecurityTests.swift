import Foundation

// App code and this file are combined by run-security-tests.sh, allowing the
// regression cases to exercise the actual private Store methods. Every home
// lookup in that build is redirected here, and discovery uses fixture Agents.
var securityTestHome = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SKILLDOCK_TEST_HOME"]!, isDirectory: true)
private let securityTestRoot = securityTestHome
private var checkedAssertions = 0
private var securityTestAgents: [InstalledAgent] = []

private struct SecurityTestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checkedAssertions += 1
    guard try condition() else { throw SecurityTestFailure(description: message) }
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
    securityTestAgents = []
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
            try check(!store.promoteToShared(cached), "Promoting must reject a stale leaf link")
            try check(exists(link.appendingPathComponent("sentinel.txt")) && exists(source), "Stale link operations must preserve both directories")
            try check(!exists(AgentKind.claude.skillDirectory.appendingPathComponent("replaced")) && !exists(store.libraryDirectory.appendingPathComponent("replaced")), "Transfers must reject a stale source")
            try check(!exists(store.sharedDirectory.appendingPathComponent("replaced")), "A stale source must not create a Shared skill")
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
            try check(!store.promoteToShared(cached), "Promoting must reject a replaced source directory")
            try check(exists(path) && exists(original), "Same-type replacements must survive stale operations")
            try check(!exists(store.sharedDirectory.appendingPathComponent(path.lastPathComponent)), "A replacement must not be promoted using the original snapshot")
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
            try check(!store.promoteToShared(cached), "A retargeted Agent root must invalidate promotion of its cached children")
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
                try check(!store.promoteToShared(item), "A managed skills container must never be promoted as a leaf skill")
                try check(exists(container.appendingPathComponent("child/sentinel.txt")), "All skills in a protected container must remain present")
                try check(!exists(store.sharedDirectory.appendingPathComponent(container.lastPathComponent)), "Promoting a container must not create a copy of all its children")
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

        try fixture("promote-agent-and-library") { store in
            let agentSource = AgentKind.codex.skillDirectory.appendingPathComponent("agent-global", isDirectory: true)
            let librarySource = store.libraryDirectory.appendingPathComponent("library-global", isDirectory: true)
            for source in [agentSource, librarySource] {
                try makeSkill(source, marker: source.lastPathComponent)
                let assets = source.appendingPathComponent("assets", isDirectory: true)
                try fm.createDirectory(at: assets, withIntermediateDirectories: true)
                try Data([0, 7, 128, 255]).write(to: assets.appendingPathComponent("fixture.bin"))
            }
            store.refresh()
            store.transferMode = .link
            store.filter = .agent
            for source in [agentSource, librarySource] {
                let item = try skill(store, at: source)
                let destination = store.sharedDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
                let promotedSuccessfully = store.promoteToShared(item)
                try check(promotedSuccessfully, "An ordinary Agent or Library skill must be promotable: \(store.notice?.message ?? "no notice")")
                try check(SkillFileIdentity.identity(at: destination)?.isDirectory == true, "Promotion must create a real directory even when transfer mode is Link")
                try check(SkillFileIdentity.identity(at: source) != SkillFileIdentity.identity(at: destination), "The promoted skill must be an independent directory")
                try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == source.lastPathComponent, "Promotion must retain the complete original source")
                try check((try? String(contentsOf: destination.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == source.lastPathComponent, "Promotion must preserve skill contents")
                try check((try? Data(contentsOf: destination.appendingPathComponent("assets/fixture.bin"))) == Data([0, 7, 128, 255]), "Promotion must preserve nested binary assets")
                let promoted = try skill(store, at: destination)
                try check(promoted.origin == .shared && !store.canDelete(promoted) && !store.canArchive(promoted), "The promoted copy must be scanned as protected Shared")
                try check(store.selectedSkillID == destination.standardizedFileURL.path, "The completed Shared copy must be selected")
            }
            try check(store.filter == .global, "Promotion from an Agent-only filter must reveal the Shared result")
            try check((try fm.contentsOfDirectory(atPath: store.sharedDirectory.path)).allSatisfy { !$0.hasPrefix(".skilldock-") }, "Successful promotion must leave no staging directories")
        }

        try fixture("promote-linked-source") { store in
            let source = securityTestHome.appendingPathComponent("outside/linked-source", isDirectory: true)
            let link = AgentKind.claude.skillDirectory.appendingPathComponent("linked-global", isDirectory: true)
            let destination = store.sharedDirectory.appendingPathComponent(link.lastPathComponent, isDirectory: true)
            try makeSkill(source, marker: "linked-source-data")
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            store.refresh()
            let item = try skill(store, at: link)
            try check(store.promoteToShared(item), "A linked Agent skill must be promotable")
            try check(SkillFileIdentity.identity(at: destination)?.isDirectory == true, "The promoted linked skill must be a real directory rather than another link")
            try check(SkillFileIdentity.identity(at: link)?.isSymbolicLink == true && exists(source), "Promotion must retain both the Agent link and its original target")
            try fm.removeItem(at: link)
            try fm.removeItem(at: source)
            try check((try? String(contentsOf: destination.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "linked-source-data", "A promoted link must remain complete after its old source is removed")
            try check(exists(destination.appendingPathComponent("SKILL.md")), "A promoted link must retain its own skill definition")
        }

        try fixture("promote-collisions") { store in
            let sourceRoot = AgentKind.claude.skillDirectory
            let ordinary = sourceRoot.appendingPathComponent("occupied", isDirectory: true)
            let dangling = sourceRoot.appendingPathComponent("dangling", isDirectory: true)
            let occupiedDestination = store.sharedDirectory.appendingPathComponent(ordinary.lastPathComponent, isDirectory: true)
            let danglingDestination = store.sharedDirectory.appendingPathComponent(dangling.lastPathComponent, isDirectory: true)
            let missing = securityTestHome.appendingPathComponent("does-not-exist", isDirectory: true)
            try makeSkill(ordinary, marker: "agent-original")
            try makeSkill(dangling, marker: "agent-linked-original")
            try makeSkill(occupiedDestination, marker: "shared-original")
            try fm.createSymbolicLink(at: danglingDestination, withDestinationURL: missing)
            store.refresh()
            let occupiedIdentity = SkillFileIdentity.identity(at: occupiedDestination)
            let danglingIdentity = SkillFileIdentity.identity(at: danglingDestination)
            try check(!store.promoteToShared(try skill(store, at: ordinary)), "A same-name Shared directory must reject promotion")
            try check(!store.promoteToShared(try skill(store, at: dangling)), "A dangling same-name Shared link must reject promotion")
            try check(SkillFileIdentity.identity(at: occupiedDestination) == occupiedIdentity && (try? String(contentsOf: occupiedDestination.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "shared-original", "Promotion must preserve an existing Shared directory and its data")
            try check(SkillFileIdentity.identity(at: danglingDestination) == danglingIdentity && (try? fm.destinationOfSymbolicLink(atPath: danglingDestination.path)) == missing.path, "Promotion must preserve an existing dangling Shared link")
            try check((try? String(contentsOf: ordinary.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "agent-original" && (try? String(contentsOf: dangling.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "agent-linked-original", "Rejected promotions must preserve both Agent sources")
        }

        try fixture("promote-already-shared") { store in
            let source = store.sharedDirectory.appendingPathComponent("already-global", isDirectory: true)
            let link = AgentKind.claude.skillDirectory.appendingPathComponent("global-alias", isDirectory: true)
            try makeSkill(source, marker: "shared-data")
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: source)
            store.refresh()
            let identity = SkillFileIdentity.identity(at: source)
            try check(!store.promoteToShared(try skill(store, at: source)), "A Shared source must be a no-op")
            try check(!store.promoteToShared(try skill(store, at: link)), "An Agent link to Shared must be a no-op instead of duplicating a global source")
            try check(SkillFileIdentity.identity(at: source) == identity && (try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "shared-data", "No-op promotion must preserve the existing Shared skill")
            try check(!exists(store.sharedDirectory.appendingPathComponent(link.lastPathComponent)), "A Shared alias must not create a duplicate under its Agent link name")
        }

        try fixture("promote-readonly-source") { store in
            let builtin = AgentKind.codex.skillDirectory.appendingPathComponent(".system/builtin-global", isDirectory: true)
            let synced = AgentKind.claude.skillDirectory.appendingPathComponent("synced/synced-global", isDirectory: true)
            for source in [builtin, synced] { try makeSkill(source, marker: "managed-original") }
            store.refresh()
            for source in [builtin, synced] {
                let item = try skill(store, at: source)
                try check(!store.canDelete(item) && !store.canArchive(item), "Managed sources must begin read-only")
                try check(store.promoteToShared(item), "A read-only managed source may be copied to Shared without modifying it")
                try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "managed-original", "Promoting must preserve managed source data")
                try check((try? String(contentsOf: store.sharedDirectory.appendingPathComponent(source.lastPathComponent).appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "managed-original", "Promoting must make a complete copy of a managed skill")
                try check(!store.canDelete(try skill(store, at: source)) && !store.canArchive(try skill(store, at: source)), "Promotion must not relax management protection for the original")
            }
        }

        for aliasKind in ["synced", "default", "agent", "plugin-cache"] {
            try fixture("promote-shared-alias-\(aliasKind)") { store in
                let source = store.libraryDirectory.appendingPathComponent("alias-global", isDirectory: true)
                let aliasTarget: URL
                switch aliasKind {
                case "synced": aliasTarget = AgentKind.claude.skillDirectory.appendingPathComponent("synced", isDirectory: true)
                case "default": aliasTarget = AgentKind.codex.skillDirectory.appendingPathComponent(".system", isDirectory: true)
                case "agent": aliasTarget = AgentKind.claude.skillDirectory
                default: aliasTarget = securityTestHome.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/generated-cache/skills", isDirectory: true)
                }
                try makeSkill(source, marker: "library-original")
                try fm.createDirectory(at: aliasTarget, withIntermediateDirectories: true)
                try "target-original".write(to: aliasTarget.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
                try fm.createDirectory(at: store.sharedDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.createSymbolicLink(at: store.sharedDirectory, withDestinationURL: aliasTarget)
                store.refresh()
                try check(!store.promoteToShared(try skill(store, at: source)), "Shared must reject an alias into another managed or protected skill root")
                try check(!exists(aliasTarget.appendingPathComponent(source.lastPathComponent)), "Rejected Shared aliases must not add skills to the target root")
                try check((try? String(contentsOf: aliasTarget.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "target-original", "Rejected Shared aliases must preserve existing target data")
                try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "library-original", "Rejected Shared aliases must preserve the source")
            }
        }

        try fixture("promote-parent-alias-missing-shared") { store in
            let source = store.libraryDirectory.appendingPathComponent("missing-global-root", isDirectory: true)
            let synced = AgentKind.claude.skillDirectory.appendingPathComponent("synced", isDirectory: true)
            try makeSkill(source)
            try fm.createDirectory(at: synced, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: store.sharedDirectory.deletingLastPathComponent(), withDestinationURL: synced)
            store.refresh()
            try check(!store.promoteToShared(try skill(store, at: source)), "A missing Shared root beneath a protected parent alias must be rejected")
            try check(!exists(synced.appendingPathComponent("skills")), "Shared validation must run before creating a missing root under a protected parent")
            try check(exists(source.appendingPathComponent("sentinel.txt")), "A rejected missing-root promotion must retain its source")
        }

        try fixture("promote-recursive-alias") { store in
            let source = store.libraryDirectory.appendingPathComponent("recursive", isDirectory: true)
            let nested = source.appendingPathComponent("nested-global", isDirectory: true)
            try makeSkill(source, marker: "recursive-original")
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            try fm.createDirectory(at: store.sharedDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: store.sharedDirectory, withDestinationURL: nested)
            store.refresh()
            try check(!store.promoteToShared(try skill(store, at: source)), "Shared inside the source must reject recursive copying")
            try check((try fm.contentsOfDirectory(atPath: nested.path)).isEmpty, "A recursive copy rejection must leave the nested destination empty")
            try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "recursive-original", "A recursive copy rejection must preserve source data")
        }

        try fixture("mirasim-user-management") { store in
            let source = AgentKind.mirasim.skillDirectory.appendingPathComponent("user-global", isDirectory: true)
            let library = store.libraryDirectory.appendingPathComponent("link-to-mirasim", isDirectory: true)
            try makeSkill(source, marker: "mirasim-user-original")
            try makeSkill(library, marker: "library-for-mirasim")
            store.refresh()
            let user = try skill(store, at: source)
            try check(user.origin == .agent(.mirasim) && user.defaultAgent == nil, "A Mirasim user skill must be scanned as an ordinary Agent skill")
            try check(store.canDelete(user) && store.canArchive(user), "A Mirasim user skill must support ordinary management")
            try check(store.skills(for: .mirasim).contains(where: { $0.id == user.id }), "Mirasim's skill list must include its local user skills")
            try check(store.promoteToShared(user), "A Mirasim user skill must be promotable")
            let shared = store.sharedDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            let sharedItem = try skill(store, at: shared)
            try check(store.isInstalled(sharedItem, in: .mirasim), "Mirasim must treat Shared skills as automatically installed")
            try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "mirasim-user-original", "Making a Mirasim skill global must retain its local source")
            store.transfer(try skill(store, at: library), to: .mirasim, mode: .link)
            let linked = AgentKind.mirasim.skillDirectory.appendingPathComponent(library.lastPathComponent, isDirectory: true)
            try check(SkillFileIdentity.identity(at: linked)?.isSymbolicLink == true, "Mirasim must accept an ordinary linked skill")
            store.delete(try skill(store, at: linked))
            try check(SkillFileIdentity.identity(at: linked) == nil && exists(library.appendingPathComponent("sentinel.txt")), "Removing a Mirasim skill link must preserve its Library source")
            store.archive(try skill(store, at: source))
            try check(!exists(source) && exists(store.archivedDirectory.appendingPathComponent(source.lastPathComponent).appendingPathComponent("sentinel.txt")), "A Mirasim user skill must archive normally")
            try check((try? String(contentsOf: shared.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "mirasim-user-original", "Managing a Mirasim local source must retain its independent global copy")
            try check(store.skills(for: .mirasim).contains(where: { $0.origin == .shared && $0.path.standardizedFileURL.path == shared.standardizedFileURL.path }), "Mirasim's skill list must include Shared when its same-name local copy is absent")
        }

        try fixture("mirasim-managed-defaults") { store in
            let builtInNames = ["eval", "mirasim-guide", "mirasim-operate", "mirasim-publish"]
            for name in builtInNames {
                let source = AgentKind.mirasim.skillDirectory.appendingPathComponent(name, isDirectory: true)
                try makeSkill(source, marker: "managed-\(name)")
                let marker = try JSONSerialization.data(withJSONObject: ["name": name, "fingerprint": String(repeating: "a", count: 64)])
                try marker.write(to: source.appendingPathComponent(".mirasim-skill.json"))
            }
            let ordinary = AgentKind.mirasim.skillDirectory.appendingPathComponent("ordinary", isDirectory: true)
            let library = store.libraryDirectory.appendingPathComponent("mixed-root-link", isDirectory: true)
            try makeSkill(ordinary)
            try makeSkill(library)
            store.refresh()
            try check(!store.expandedDefaultAgents.contains(.mirasim), "Mirasim default skills must begin collapsed")
            for name in builtInNames {
                let source = AgentKind.mirasim.skillDirectory.appendingPathComponent(name, isDirectory: true)
                let item = try skill(store, at: source)
                try check(item.isDefault && item.defaultAgent == .mirasim, "A Mirasim built-in with its valid marker must be classified for the default group")
                try check(!store.canDelete(item) && !store.canArchive(item), "Mirasim managed default skills must be read-only")
                try check(store.promoteToShared(item), "A Mirasim default skill may be copied to Shared")
                let destination = store.sharedDirectory.appendingPathComponent(name, isDirectory: true)
                try check(SkillFileIdentity.identity(at: destination)?.isDirectory == true && (try? String(contentsOf: destination.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "managed-\(name)", "A promoted Mirasim default must be a complete independent copy")
                try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "managed-\(name)" && !store.canDelete(try skill(store, at: source)), "Promoting a default must preserve its data and read-only policy")
            }
            let ordinaryItem = try skill(store, at: ordinary)
            try check(!ordinaryItem.isDefault && store.canDelete(ordinaryItem) && store.canArchive(ordinaryItem), "Managed defaults must not lock other Mirasim user skills in the same root")
            store.transfer(try skill(store, at: library), to: .mirasim, mode: .link)
            let linked = AgentKind.mirasim.skillDirectory.appendingPathComponent(library.lastPathComponent, isDirectory: true)
            try check(SkillFileIdentity.identity(at: linked)?.isSymbolicLink == true, "A mixed Mirasim root must remain writable for ordinary transfers")
            store.delete(try skill(store, at: ordinary))
            try check(!exists(ordinary) && builtInNames.allSatisfy { exists(AgentKind.mirasim.skillDirectory.appendingPathComponent($0).appendingPathComponent("sentinel.txt")) }, "Deleting an ordinary Mirasim skill must preserve every managed default")
        }

        try fixture("mirasim-unmarked-default-names") { store in
            for name in ["eval", "mirasim-guide", "mirasim-operate", "mirasim-publish"] {
                try makeSkill(AgentKind.mirasim.skillDirectory.appendingPathComponent(name, isDirectory: true))
            }
            store.refresh()
            for name in ["eval", "mirasim-guide", "mirasim-operate", "mirasim-publish"] {
                let item = try skill(store, at: AgentKind.mirasim.skillDirectory.appendingPathComponent(name, isDirectory: true))
                try check(!item.isDefault && item.defaultAgent == nil, "A matching Mirasim skill name without the managed marker must remain a user skill")
                try check(store.canDelete(item) && store.canArchive(item), "Unmarked names must not gain default-skill restrictions")
            }
            let invalidMarkers: [String: [String: String]] = [
                "eval": ["name": "other-skill", "fingerprint": String(repeating: "a", count: 64)],
                "mirasim-guide": ["name": "mirasim-guide", "fingerprint": ""],
                "mirasim-operate": ["name": "mirasim-operate", "fingerprint": String(repeating: "z", count: 64)],
                "mirasim-publish": ["fingerprint": String(repeating: "b", count: 64)]
            ]
            for (name, marker) in invalidMarkers {
                let markerFile = AgentKind.mirasim.skillDirectory.appendingPathComponent(name).appendingPathComponent(".mirasim-skill.json")
                try JSONSerialization.data(withJSONObject: marker).write(to: markerFile)
            }
            store.refresh()
            for name in invalidMarkers.keys {
                let item = try skill(store, at: AgentKind.mirasim.skillDirectory.appendingPathComponent(name, isDirectory: true))
                try check(!item.isDefault && store.canDelete(item) && store.canArchive(item), "A malformed or mismatched Mirasim marker must not restrict a user skill")
            }
        }

        try runAgentSkillTests()
        print("Store security regressions passed (\(checkedAssertions) assertions).")
    }
}
