import Foundation

@MainActor
private func runOrganizationStoreTests() async throws {
    let fm = FileManager.default
    var subject: SkillStore!
    try fixture("organization-store") { store in
        let shared = store.sharedDirectory.appendingPathComponent("retained")
        try makeSkill(shared)
        for root in [AgentKind.codex.skillDirectory, AgentKind.claude.skillDirectory, store.archivedDirectory,
                     AgentKind.claude.skillDirectory.appendingPathComponent("synced")] {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try fm.copyItem(at: shared, to: root.appendingPathComponent("retained"))
        }
        store.refresh()
        subject = store
        try check(!store.canConvertCopy(try skill(store, at: shared)), "Shared originals must never be replaced")
        try check(store.canConvertCopy(try skill(store, at: AgentKind.codex.skillDirectory.appendingPathComponent("retained"))), "Editable Agent copies must support conversion")
    }
    let store = subject!
    func waitForWork() async throws {
        for _ in 0..<2000 {
            if !store.scanningDuplicates && !store.organizingSkills { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try check(false, "Organization background work must finish")
    }
    store.openOrganizer()
    try await waitForWork()
    try check(store.organizerError == nil && store.duplicateScan?.groups.count == 1, "The Store must publish an identical-copy scan")
    let group = store.duplicateScan!.groups[0]
    try check(group.source.path == store.sharedDirectory.appendingPathComponent("retained") && !group.source.canReplace,
              "One-click organization must prefer the existing Shared original")
    try check(group.copies.count == 2 && group.copies.allSatisfy(\.canReplace), "Archived and synced copies must be excluded from organization")
    let initialSelection = SkillOrganizationSelection(groups: [group])
    try check(initialSelection.entries(in: [group], focusID: nil).count == 2, "Batch review must initially select every editable duplicate")
    let focused = group.copies[0]
    var focusedSelection = SkillOrganizationSelection(groups: [group], focusID: focused.id)
    focusedSelection.toggleCopy(group.copies[1].id, selected: true)
    let focusedPlan = focusedSelection.entries(in: [group], focusID: focused.id)
    try check(focusedPlan.count == 1 && focusedPlan[0].copy.id == focused.id,
              "Single-copy conversion must never include a different copy")
    focusedSelection.chooseSource(focused, in: group, focusID: focused.id)
    try check(focusedSelection.sourceIDs[group.id] == group.source.id, "A focused copy cannot become its own original")
    let localGroup = SkillDuplicateGroup(id: group.id, source: focused, copies: [group.copies[1]])
    let localSelection = SkillOrganizationSelection(groups: [localGroup], focusID: focused.id)
    let localPlan = localSelection.entries(in: [localGroup], focusID: focused.id)
    try check(localPlan.count == 1 && localPlan[0].source.id == group.copies[1].id && localPlan[0].copy.id == focused.id,
              "Single-copy conversion must retain another original when the focused copy has the highest priority")
    let plan = group.copies.map { SkillDuplicatePlanEntry(source: group.source, copy: $0, fingerprint: group.fingerprint) }
    store.organizeCopies(plan)
    try await waitForWork()
    try check(store.organizerError == nil && store.lastOrganization?.records.count == 2, "The Store must publish its reversible organization batch")
    for copy in group.copies {
        let item = try skill(store, at: copy.path)
        try check(item.isSymbolicLink && store.installedSkillSubtitle(item).contains("~/.agents/skills"), "Converted Agent entries must display their Shared link source")
        try check(!store.canConvertCopy(item), "A link must not be offered as a convertible copy")
    }
    try check(exists(store.archivedDirectory.appendingPathComponent("retained/sentinel.txt")), "Organizing must preserve archived skills")
    let reloadDefaults = UserDefaults(suiteName: "SkillDock.OrganizationReload.\(UUID().uuidString)")!
    let reloaded = SkillStore(defaults: reloadDefaults)
    try check(reloaded.lastOrganization?.id == store.lastOrganization?.id, "A restarted Store must find the saved batch")
    reloaded.restoreLastOrganization()
    for _ in 0..<2000 {
        if !reloaded.organizingSkills { break }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    try check(reloaded.organizerError == nil && !reloaded.organizingSkills, "A restarted Store must restore its last organization")
    for copy in group.copies {
        try check(SkillFileIdentity.identity(at: copy.path)?.isDirectory == true, "Restore must recover each independent directory")
    }
    store.openOrganizer()
    try await waitForWork()
    let stale = store.duplicateScan!.groups[0]
    let changed = stale.copies[0]
    try "new edit".write(to: changed.path.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
    store.organizeCopies([SkillDuplicatePlanEntry(source: stale.source, copy: changed, fingerprint: stale.fingerprint)])
    try await waitForWork()
    try check(store.organizerError != nil && SkillFileIdentity.identity(at: changed.path)?.isDirectory == true,
              "The Store must surface a stale scan without replacing an edited copy")
    store.openOrganizer()
    store.cancelDuplicateScan()
    try await Task.sleep(nanoseconds: 20_000_000)
    try check(!store.scanningDuplicates && store.duplicateScan == nil, "A cancelled scan must not publish stale results")
}
