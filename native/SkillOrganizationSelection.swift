import Foundation

/// The review selection shared by the batch and single-copy organizer views.
struct SkillOrganizationSelection {
    private(set) var sourceIDs: [String: String] = [:]
    private(set) var copyIDs = Set<String>()

    init(groups: [SkillDuplicateGroup] = [], focusID: String? = nil) {
        for group in groups {
            let members = [group.source] + group.copies
            let source = group.source.id == focusID ? members.first { $0.id != focusID } : group.source
            if let source { chooseSource(source, in: group, focusID: focusID) }
        }
    }

    mutating func chooseSource(_ source: SkillDuplicateCandidate, in group: SkillDuplicateGroup, focusID: String?) {
        let members = [group.source] + group.copies
        guard source.id != focusID, members.contains(where: { $0.id == source.id }) else { return }
        sourceIDs[group.id] = source.id
        for member in members {
            if member.id != source.id && member.canReplace && (focusID == nil || member.id == focusID) {
                copyIDs.insert(member.id)
            } else { copyIDs.remove(member.id) }
        }
    }

    mutating func toggleCopy(_ id: String, selected: Bool) {
        if selected { copyIDs.insert(id) } else { copyIDs.remove(id) }
    }

    func entries(in groups: [SkillDuplicateGroup], focusID: String?) -> [SkillDuplicatePlanEntry] {
        groups.flatMap { group -> [SkillDuplicatePlanEntry] in
            let members = [group.source] + group.copies
            let source = members.first { $0.id == sourceIDs[group.id] } ?? group.source
            return members.filter {
                $0.id != source.id && $0.canReplace && copyIDs.contains($0.id) && (focusID == nil || $0.id == focusID)
            }.map { SkillDuplicatePlanEntry(source: source, copy: $0, fingerprint: group.fingerprint) }
        }
    }
}
