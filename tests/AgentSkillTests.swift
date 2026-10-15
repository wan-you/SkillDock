import Foundation

// The runner appends this file to the isolated Store test build. Installed
// commands are fixture inventory only; no command or application is launched.
@MainActor
private func runAgentSkillTests() throws {
    try fixture("grok-command-user-management", setup: { home in
        securityTestAgents = [InstalledAgent(
            kind: .grok, applicationURL: nil, bundleIdentifier: "", applicationName: "Grok",
            executableURL: home.appendingPathComponent(".grok/bin/grok")
        )]
        try makeSkill(home.appendingPathComponent(".grok/skills/grok-personal"), marker: "grok-original")
        try makeSkill(home.appendingPathComponent(".agents/skills/shared-for-grok"), marker: "shared-original")
    }) { store in
        let root = AgentKind.grok.skillDirectory
        let source = root.appendingPathComponent("grok-personal", isDirectory: true)
        let shared = store.sharedDirectory.appendingPathComponent("shared-for-grok", isDirectory: true)
        let user = try skill(store, at: source)
        let sharedItem = try skill(store, at: shared)
        try check(store.agents.count == 1 && store.agents.first?.kind == .grok, "A command-only Grok inventory must appear as an installed Agent")
        try check(store.agents.first?.isCommandLine == true && store.agents.first?.applicationURL == nil, "Grok CLI integration must not require a GUI application")
        try check(user.origin == .agent(.grok) && !user.isDefault, "Grok user skills must have an ordinary Grok origin")
        try check(store.canDelete(user) && store.canArchive(user), "Ordinary Grok skills must remain manageable")
        try check(store.skills(for: .grok).contains(where: { $0.id == user.id }), "Grok must list its personal skills")
        try check(store.skills(for: .grok).contains(where: { $0.id == sharedItem.id }) && store.isInstalled(sharedItem, in: .grok), "Grok must automatically include Shared skills")
        try check(store.relationships(for: sharedItem).downstream.contains(where: { $0.id == "agent:grok" }), "A Shared skill must show the installed Grok Agent downstream")
        try check(!store.canDelete(sharedItem) && !store.canArchive(sharedItem), "Grok's automatic Shared access must preserve Shared read-only policy")
        try check(store.promoteToShared(user), "A Grok user skill must support promotion to Shared")
        let promoted = store.sharedDirectory.appendingPathComponent(source.lastPathComponent)
        try check(exists(source.appendingPathComponent("sentinel.txt")) && exists(promoted.appendingPathComponent("sentinel.txt")), "Promoting a Grok skill must retain the original and copy its contents")
        try check(SkillFileIdentity.identity(at: source) != SkillFileIdentity.identity(at: promoted), "A promoted Grok skill must be an independent directory")

        let library = store.libraryDirectory.appendingPathComponent("grok-linked", isDirectory: true)
        try makeSkill(library, marker: "grok-link-source")
        store.refresh()
        store.transfer(try skill(store, at: library), to: .grok, mode: .link)
        let linked = root.appendingPathComponent(library.lastPathComponent, isDirectory: true)
        let linkItem = try skill(store, at: linked)
        try check(linkItem.isSymbolicLink && store.canDelete(linkItem) && !store.canArchive(linkItem), "Grok must accept removable Library links")
        store.delete(linkItem)
        try check(SkillFileIdentity.identity(at: linked) == nil && exists(library.appendingPathComponent("sentinel.txt")), "Removing a Grok link must preserve its Library source")
        store.transfer(try skill(store, at: library), to: .grok, mode: .copy)
        let copied = try skill(store, at: linked)
        try check(!copied.isSymbolicLink && store.canArchive(copied), "Grok must accept independent copies after a link is removed")
        store.delete(copied)
        try check(!exists(linked) && exists(library), "Deleting a copied Grok skill must preserve Library")
        store.archive(try skill(store, at: source))
        let archived = store.archivedDirectory.appendingPathComponent(source.lastPathComponent)
        try check(!exists(source) && exists(archived.appendingPathComponent("sentinel.txt")), "A Grok personal skill must archive normally")
        try check((try? String(contentsOf: promoted.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "grok-original", "Archiving Grok's original must preserve the promoted Shared copy")
    }

    try fixture("grok-bundled-defaults", setup: { home in
        securityTestAgents = [InstalledAgent(
            kind: .grok, applicationURL: nil, bundleIdentifier: "", applicationName: "Grok",
            executableURL: home.appendingPathComponent(".grok/bin/grok")
        )]
        for name in ["pdf", "docx"] {
            try makeSkill(home.appendingPathComponent(".grok/bundled/skills/\(name)"), marker: "bundled-\(name)")
        }
        try makeSkill(home.appendingPathComponent(".grok/skills/personal-next-to-bundle"))
    }) { store in
        let bundledRoot = AgentKind.grokDataDirectory(home: securityTestHome).appendingPathComponent("bundled/skills", isDirectory: true)
        try check(!store.expandedDefaultAgents.contains(.grok), "Grok defaults must begin collapsed")
        try check(store.skills(for: .grok).filter(\.isDefault).count == 2, "Grok must scan its bundled default definitions")
        let expansion = store.defaultSkillsExpansion(for: .grok)
        expansion.wrappedValue = true
        try check(store.expandedDefaultAgents.contains(.grok), "Grok's default group must support expansion")
        expansion.wrappedValue = false
        try check(!store.expandedDefaultAgents.contains(.grok), "Grok's default group must support collapsing again")
        for name in ["pdf", "docx"] {
            let source = bundledRoot.appendingPathComponent(name, isDirectory: true)
            let bundled = try skill(store, at: source)
            try check(bundled.origin == .agent(.grok) && bundled.defaultAgent == .grok && bundled.isDefault, "A Grok bundled skill must belong to Grok's default group")
            try check(!store.canDelete(bundled) && !store.canArchive(bundled), "Grok bundled skills must be read-only")
            store.delete(bundled)
            store.archive(bundled)
            try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "bundled-\(name)", "Blocked Grok default management must preserve the original")
            try check(store.promoteToShared(bundled), "A Grok bundled skill may be copied to Shared")
            let promoted = store.sharedDirectory.appendingPathComponent(name, isDirectory: true)
            let global = try skill(store, at: promoted)
            try check(global.origin == .shared && !global.isDefault && !global.isSymbolicLink, "Promoted Grok defaults must become ordinary independent Shared copies")
            try check((try? String(contentsOf: promoted.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "bundled-\(name)", "Promoting a Grok default must copy its full contents")
            try check(SkillFileIdentity.identity(at: promoted) != SkillFileIdentity.identity(at: source), "A Grok default's global copy must not alias the bundled directory")
            try check(!store.canDelete(try skill(store, at: source)) && exists(source), "Promoting Grok defaults must preserve their read-only source")
        }
        let bundled = try skill(store, at: bundledRoot.appendingPathComponent("pdf"))
        store.copyToLibrary(bundled)
        let libraryCopy = try skill(store, at: store.libraryDirectory.appendingPathComponent("pdf"))
        try check(!libraryCopy.isDefault && store.canDelete(libraryCopy), "A Grok default copied into Library must become a manageable personal copy")
        let personal = try skill(store, at: AgentKind.grok.skillDirectory.appendingPathComponent("personal-next-to-bundle"))
        try check(!personal.isDefault && store.canDelete(personal) && store.canArchive(personal), "Protecting Grok's bundled subtree must not lock its ordinary user root")
        let extraLibrary = store.libraryDirectory.appendingPathComponent("grok-extra-user-skill", isDirectory: true)
        try makeSkill(extraLibrary)
        store.refresh()
        store.transfer(try skill(store, at: extraLibrary), to: .grok, mode: .copy)
        let installed = try skill(store, at: AgentKind.grok.skillDirectory.appendingPathComponent(extraLibrary.lastPathComponent))
        try check(!installed.isDefault && store.canDelete(installed), "Grok's personal root must remain writable while its bundled skills are protected")
        store.delete(installed)
        try check(!exists(installed.path) && exists(bundled.path), "Deleting a Grok personal override must preserve the bundled default")
    }

    try fixture("deepseek-command-package-defaults", setup: { home in
        let package = home.appendingPathComponent("fixtures/dsh-package", isDirectory: true)
        securityTestAgents = [InstalledAgent(
            kind: .deepseek, applicationURL: nil, bundleIdentifier: "", applicationName: "DeepSeek Harness",
            executableURL: home.appendingPathComponent(".local/bin/dsh"), packageRootURL: package
        )]
        for name in ["docx", "pptx", "xlsx"] {
            try makeSkill(package.appendingPathComponent("node_modules/@deepseek-ai/dsh-skill-office/assets/\(name)"), marker: "dsh-bundled-\(name)")
        }
        try makeSkill(home.appendingPathComponent(".dsh/skills/dsh-personal"), marker: "dsh-user-original")
        try makeSkill(home.appendingPathComponent(".agents/skills/shared-for-dsh"), marker: "shared-for-dsh")
    }) { store in
        guard let detected = store.agents.first(where: { $0.kind == .deepseek }), let package = detected.packageRootURL else {
            throw SecurityTestFailure(description: "DeepSeek command fixture inventory must retain its package root")
        }
        let assets = package.appendingPathComponent("node_modules/@deepseek-ai/dsh-skill-office/assets", isDirectory: true)
        try check(detected.isCommandLine && detected.applicationURL == nil, "DeepSeek CLI integration must not require a GUI application")
        try check(!store.expandedDefaultAgents.contains(.deepseek), "DeepSeek CLI defaults must begin collapsed")
        try check(store.skills(for: .deepseek).filter(\.isDefault).count == 3, "DeepSeek must scan all three package office defaults")
        for name in ["docx", "pptx", "xlsx"] {
            let source = assets.appendingPathComponent(name, isDirectory: true)
            let bundled = try skill(store, at: source)
            try check(bundled.origin == .agent(.deepseek) && bundled.defaultAgent == .deepseek, "DeepSeek package skills must belong to its default group")
            try check(!store.canDelete(bundled) && !store.canArchive(bundled), "DeepSeek package default skills must remain read-only")
            store.delete(bundled)
            store.archive(bundled)
            try check((try? String(contentsOf: source.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "dsh-bundled-\(name)", "Blocked DeepSeek default management must preserve package data")
            try check(store.promoteToShared(bundled), "A DeepSeek package default may be copied to Shared")
            let promoted = store.sharedDirectory.appendingPathComponent(name, isDirectory: true)
            let global = try skill(store, at: promoted)
            try check(global.origin == .shared && !global.isDefault && !global.isSymbolicLink, "A promoted DeepSeek default must become an independent Shared skill")
            try check((try? String(contentsOf: promoted.appendingPathComponent("sentinel.txt"), encoding: .utf8)) == "dsh-bundled-\(name)" && exists(source), "A promoted DeepSeek default must preserve source and copy contents")
        }
        let userPath = AgentKind.deepseek.skillDirectory.appendingPathComponent("dsh-personal", isDirectory: true)
        let user = try skill(store, at: userPath)
        let shared = try skill(store, at: store.sharedDirectory.appendingPathComponent("shared-for-dsh"))
        try check(user.origin == .agent(.deepseek) && !user.isDefault && store.canDelete(user) && store.canArchive(user), "DeepSeek package protections must leave .dsh personal skills manageable")
        try check(store.skills(for: .deepseek).contains(where: { $0.id == shared.id }) && store.isInstalled(shared, in: .deepseek), "DeepSeek CLI must automatically include Shared skills")
        try check(store.relationships(for: shared).downstream.contains(where: { $0.id == "agent:deepseek" }), "Shared relationships must include an installed command-only DeepSeek Agent")
        try check(store.promoteToShared(user), "DeepSeek personal skills must support promotion to Shared")
        let library = store.libraryDirectory.appendingPathComponent("dsh-linked", isDirectory: true)
        try makeSkill(library, marker: "dsh-library-source")
        store.refresh()
        store.transfer(try skill(store, at: library), to: .deepseek, mode: .link)
        let linkedPath = AgentKind.deepseek.skillDirectory.appendingPathComponent(library.lastPathComponent)
        let linked = try skill(store, at: linkedPath)
        try check(linked.isSymbolicLink && store.canDelete(linked), "DeepSeek CLI personal skills must accept Library links")
        store.delete(linked)
        try check(SkillFileIdentity.identity(at: linkedPath) == nil && exists(library.appendingPathComponent("sentinel.txt")), "Deleting a DeepSeek link must preserve Library")
        store.transfer(try skill(store, at: library), to: .deepseek, mode: .copy)
        let copied = try skill(store, at: linkedPath)
        try check(!copied.isSymbolicLink && store.canDelete(copied) && store.canArchive(copied), "DeepSeek CLI must accept manageable independent copies")
        store.archive(copied)
        try check(!exists(linkedPath) && exists(store.archivedDirectory.appendingPathComponent(library.lastPathComponent)), "DeepSeek copied user skills must archive normally")
        store.delete(try skill(store, at: userPath))
        try check(!exists(userPath) && exists(store.sharedDirectory.appendingPathComponent(userPath.lastPathComponent).appendingPathComponent("sentinel.txt")), "Deleting a DeepSeek original must preserve its promoted Shared copy")
        try check(["docx", "pptx", "xlsx"].allSatisfy { exists(assets.appendingPathComponent($0).appendingPathComponent("sentinel.txt")) }, "DeepSeek user operations must preserve all package defaults")
    }

    try fixture("skill-description-block-scalars", setup: { home in
        for (folder, indicator) in [("folded", ">"), ("folded-strip", ">-"), ("literal", "|"), ("literal-strip", "|-")] {
            let path = home.appendingPathComponent(".grok/skills/\(folder)", isDirectory: true)
            try makeSkill(path)
            let definition = """
            ---
            description: \(indicator)
              First description line.
              Second description line: details.
            version: 1.2.3
            name: Scalar example
            ---
            BODY_SENTINEL must remain outside the description.
            description: BODY_SENTINEL is not frontmatter.
            """
            try definition.write(to: path.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
    }) { store in
        let folded = try ["folded", "folded-strip"].map { try skill(store, at: AgentKind.grok.skillDirectory.appendingPathComponent($0)) }
        let literal = try ["literal", "literal-strip"].map { try skill(store, at: AgentKind.grok.skillDirectory.appendingPathComponent($0)) }
        let all = folded + literal
        try check(folded.allSatisfy { $0.description == "First description line. Second description line: details." }, "Folded description scalars must join indented lines with spaces for both > and >-")
        try check(literal.allSatisfy { $0.description.trimmingCharacters(in: .newlines) == "First description line.\nSecond description line: details." }, "Literal description scalars must retain internal line breaks for both | and |-")
        try check(all.allSatisfy { $0.name == "Scalar example" && $0.version == "1.2.3" }, "A block description must stop before following top-level name and version fields")
        try check(all.allSatisfy { !$0.description.contains("BODY_SENTINEL") && !$0.description.contains("version:") && !$0.description.contains("name:") }, "Description scalars must exclude later metadata fields and the body after the closing frontmatter delimiter")
    }
}
