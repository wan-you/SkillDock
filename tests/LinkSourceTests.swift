import Foundation

// These cases use the isolated home supplied by run-security-tests.sh.
@MainActor
private func runLinkSourceTests() throws {
    let fm = FileManager.default
    func link(_ path: URL, to destination: String) throws {
        try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: path.path, withDestinationPath: destination)
    }
    func has(_ nodes: [SkillRelationNode], _ item: SkillItem) -> Bool {
        nodes.contains { $0.id == "skill:\(item.id)" }
    }
    func mentions(_ nodes: [SkillRelationNode], _ path: String) -> Bool {
        nodes.contains { $0.title.contains(path) || $0.detail.contains(path) }
    }

    try fixture("link-source-transfer") { store in
        let source = AgentKind.codex.skillDirectory.appendingPathComponent("songshan-lake-hpc")
        try makeSkill(source, marker: "codex-original")
        store.refresh()
        store.transfer(try skill(store, at: source), to: .claude, mode: .link)
        let destination = AgentKind.claude.skillDirectory.appendingPathComponent(source.lastPathComponent)
        let original = try skill(store, at: source), installed = try skill(store, at: destination)
        try check(installed.isSymbolicLink && installed.origin == .agent(.claude), "A transferred link must remain a Claude installation")
        try check(store.installedSkillSubtitle(installed) == "链接自 Codex", "A Codex-to-Claude transfer must display Codex as its source")
        let target = try fm.destinationOfSymbolicLink(atPath: destination.path)
        try check(target.hasPrefix("/") && URL(fileURLWithPath: target).resolvingSymlinksInPath().path == source.resolvingSymlinksInPath().path, "Transfer must keep its absolute Codex target")
        try check(exists(source.appendingPathComponent("sentinel.txt")) && exists(destination.appendingPathComponent("SKILL.md")), "Source inspection must preserve both original and installed link")
        try check(has(store.relationships(for: installed).upstream, original) && has(store.relationships(for: original).downstream, installed), "Transfer relationships must point from Codex to Claude")
        store.language = .english
        try check(store.installedSkillSubtitle(installed) == "Linked from Codex", "Linked-source subtitles must follow the English language setting")
        store.language = .simplifiedChinese
        try check(store.installedSkillSubtitle(installed) == "链接自 Codex", "Linked-source subtitles must switch back immediately")
    }

    try fixture("link-source-relative-renamed") { store in
        let source = AgentKind.codex.skillDirectory.appendingPathComponent("原始 source")
        let destination = AgentKind.claude.skillDirectory.appendingPathComponent("renamed-link")
        try makeSkill(source)
        try link(destination, to: "../../.codex/skills/原始 source")
        store.refresh()
        let original = try skill(store, at: source), installed = try skill(store, at: destination)
        try check(store.installedSkillSubtitle(installed) == "链接自 Codex", "A renamed relative link must identify its source Agent")
        try check(has(store.relationships(for: installed).upstream, original), "Relative targets must create an upstream edge to the actual source")
        try check(has(store.relationships(for: original).downstream, installed), "The original must include a renamed relative link downstream")
    }

    try fixture("link-source-chain-and-peers") { store in
        let source = AgentKind.codex.skillDirectory.appendingPathComponent("chain-source")
        let middle = AgentKind.claude.skillDirectory.appendingPathComponent("chain-middle")
        let leaf = AgentKind.mirasim.skillDirectory.appendingPathComponent("chain-leaf")
        let peer = AgentKind.grok.skillDirectory.appendingPathComponent("source-peer")
        try makeSkill(source)
        try link(middle, to: source.path)
        try link(leaf, to: middle.path)
        try link(peer, to: source.path)
        store.refresh()
        let a = try skill(store, at: source), b = try skill(store, at: middle)
        let c = try skill(store, at: leaf), d = try skill(store, at: peer)
        let ar = store.relationships(for: a), br = store.relationships(for: b)
        let cr = store.relationships(for: c), dr = store.relationships(for: d)
        try check(store.installedSkillSubtitle(b) == "链接自 Codex" && store.installedSkillSubtitle(c) == "链接自 Claude Desktop", "A link chain must report each immediate source")
        try check(has(ar.downstream, b) && has(ar.downstream, d) && !has(ar.downstream, c), "A source must show direct users without skipping intermediate links")
        try check(has(br.upstream, a) && has(br.downstream, c) && !has(br.downstream, d), "A middle link must point from its source to its direct dependent")
        try check(has(cr.upstream, b) && !has(cr.upstream, a) && !has(cr.downstream, b), "A leaf must retain its middle source without reversing the chain")
        try check(has(dr.upstream, a) && !has(dr.downstream, b) && !has(dr.downstream, c), "Links sharing the same source must not become one another's downstream")
        try check(!has(br.upstream, d) && !has(dr.upstream, b), "Peer links must not become one another's upstream")
    }

    try fixture("link-source-relative-aliased-parent") { store in
        let actualRoot = securityTestHome.appendingPathComponent("storage/claude/skills")
        let source = securityTestHome.appendingPathComponent("storage/claude/sources/correct")
        let decoy = securityTestHome.appendingPathComponent(".claude/sources/correct")
        try makeSkill(source, marker: "actual-parent")
        try makeSkill(decoy, marker: "lexical-parent-decoy")
        try fm.createDirectory(at: actualRoot, withIntermediateDirectories: true)
        try link(AgentKind.claude.skillDirectory, to: actualRoot.path)
        let installedPath = AgentKind.claude.skillDirectory.appendingPathComponent("relative-parent")
        try link(installedPath, to: "../sources/correct")
        store.refresh()
        let installed = try skill(store, at: installedPath)
        try check(store.installedSkillSubtitle(installed) == "链接自 ~/storage/claude/sources/correct", "A relative target under an aliased parent must use the real parent")
        try check(mentions(store.relationships(for: installed).upstream, "~/storage/claude/sources/correct"), "External upstream details must reflect the real relative target")
        try check((try String(contentsOf: installedPath.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "actual-parent", "The fixture must resolve to the physical parent's source")
    }

    try fixture("link-source-explicit-codex-root-alias") { store in
        let shared = store.sharedDirectory.appendingPathComponent("shared-through-codex")
        try makeSkill(shared)
        try link(AgentKind.codex.skillDirectory, to: store.sharedDirectory.path)
        let codexPath = AgentKind.codex.skillDirectory.appendingPathComponent(shared.lastPathComponent)
        let destination = AgentKind.claude.skillDirectory.appendingPathComponent("explicit-codex")
        try link(destination, to: codexPath.path)
        store.refresh()
        let installed = try skill(store, at: destination), codex = try skill(store, at: codexPath)
        let global = try skill(store, at: shared), upstream = store.relationships(for: installed).upstream
        try check(store.installedSkillSubtitle(installed) == "链接自 Codex", "An explicit Codex target must retain Codex's identity even if its root aliases Shared")
        try check(has(upstream, codex) && !has(upstream, global), "Source identity must follow the explicit target rather than another canonical alias")
        try check(!has(store.relationships(for: global).downstream, installed), "A canonical-equivalent global alias must not claim the explicit Codex link")
    }

    try fixture("link-source-external") { store in
        let source = securityTestHome.appendingPathComponent("external/独有 skill")
        let destination = AgentKind.claude.skillDirectory.appendingPathComponent("external-link")
        try makeSkill(source)
        try link(destination, to: source.path)
        store.refresh()
        let installed = try skill(store, at: destination)
        try check(store.installedSkillSubtitle(installed) == "链接自 ~/external/独有 skill", "An unscanned source must display its actual short path")
        try check(mentions(store.relationships(for: installed).upstream, "~/external/独有 skill"), "An unscanned source must still appear upstream")
        store.language = .english
        try check(store.installedSkillSubtitle(installed) == "Linked from ~/external/独有 skill", "External-source subtitles must support English")
    }

    try fixture("link-source-independent-copy") { store in
        let source = AgentKind.codex.skillDirectory.appendingPathComponent("copied-skill")
        try makeSkill(source)
        store.refresh()
        store.transfer(try skill(store, at: source), to: .claude, mode: .copy)
        let original = try skill(store, at: source)
        let copied = try skill(store, at: AgentKind.claude.skillDirectory.appendingPathComponent(source.lastPathComponent))
        try check(!copied.isSymbolicLink && store.installedSkillSubtitle(copied) == copied.path.path, "An independent copy must display its local path")
        try check(!has(store.relationships(for: copied).upstream, original) && !has(store.relationships(for: original).downstream, copied), "Matching names alone must not create a copied-skill relationship")
    }

    try fixture("link-source-intermediate-alias-dotdot") { store in
        let source = AgentKind.codex.skillDirectory.appendingPathComponent("actual-source")
        let physicalChild = AgentKind.codex.skillDirectory.appendingPathComponent("child")
        let root = AgentKind.claude.skillDirectory
        let destination = root.appendingPathComponent("installed")
        let lexicalDecoy = root.appendingPathComponent(source.lastPathComponent)
        try makeSkill(source, marker: "physical-source")
        try fm.createDirectory(at: physicalChild, withIntermediateDirectories: true)
        try link(root.appendingPathComponent("alias"), to: physicalChild.path)
        try link(destination, to: "alias/../actual-source")
        store.refresh()
        let original = try skill(store, at: source), installed = try skill(store, at: destination)
        try check(!exists(lexicalDecoy) && store.installedSkillSubtitle(installed) == "链接自 Codex", "An intermediate alias before .. must identify the existing physical source instead of a missing lexical path")
        try check(has(store.relationships(for: installed).upstream, original) && has(store.relationships(for: original).downstream, installed), "An intermediate alias before .. must retain both direct relationship edges")
        try check((try String(contentsOf: destination.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "physical-source", "The fixture must follow the intermediate alias before resolving ..")

        try makeSkill(lexicalDecoy, marker: "lexical-decoy")
        store.refresh()
        let updatedOriginal = try skill(store, at: source), updatedInstalled = try skill(store, at: destination)
        let decoy = try skill(store, at: lexicalDecoy)
        try check(store.installedSkillSubtitle(updatedInstalled) == "链接自 Codex", "An existing lexical decoy must not replace the physical link source")
        let upstream = store.relationships(for: updatedInstalled).upstream
        try check(has(upstream, updatedOriginal) && !has(upstream, decoy), "An existing lexical decoy must not be shown upstream")
        try check(has(store.relationships(for: updatedOriginal).downstream, updatedInstalled) && !has(store.relationships(for: decoy).downstream, updatedInstalled), "Only the physical source may claim the installed link downstream")
    }

    try fixture("link-source-unresolvable") { store in
        let root = AgentKind.claude.skillDirectory
        try link(root.appendingPathComponent("cycle-a"), to: "cycle-b")
        try link(root.appendingPathComponent("cycle-b"), to: "cycle-a")
        try link(root.appendingPathComponent("dangling"), to: "missing")
        store.refresh()
        try check(!store.skills.contains { $0.path.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path }, "Cyclic and dangling links must be excluded from skill scanning")
    }
}
