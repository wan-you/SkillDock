import Foundation

enum SkillDuplicateMessages {
    static func text(_ message: String, chinese: Bool) -> String {
        guard chinese else { return message }
        if let translated = messages[message] { return translated }

        let retained = " The retained originals are in "
        let stopped = ". Recovery stopped because a path changed: "
        if let first = message.range(of: retained),
           let second = message.range(of: stopped, range: first.upperBound..<message.endIndex) {
            let cause = String(message[..<first.lowerBound])
            let path = String(message[first.upperBound..<second.lowerBound])
            let recovery = String(message[second.upperBound...])
            return "\(text(cause, chinese: true)) 整理前的副本保存在 \(path)。恢复因路径变化而停止：\(text(recovery, chinese: true))"
        }

        let pathMessages: [(String, String, String)] = [
            ("Contains a symbolic link: ", ".", "含有软链接："),
            ("Contains a special file: ", ".", "含有特殊文件："),
            ("A skill changed after the scan: ", ". Scan again.", "技能在扫描后发生变化，请重新扫描："),
            ("Skill folders overlap: ", ".", "技能目录重叠：")
        ]
        for (prefix, suffix, translated) in pathMessages
        where message.hasPrefix(prefix) && message.hasSuffix(suffix) {
            return translated + message.dropFirst(prefix.count).dropLast(suffix.count)
        }
        for (action, translated) in actions where message.hasPrefix(action + ": ") {
            return translated + "：" + message.dropFirst(action.count + 2)
        }
        return message
    }

    private static let messages: [String: String] = [
        "No copies were selected.": "请先选择要整理的副本。",
        "Select distinct, replaceable copies from a current duplicate scan.": "请重新扫描并选择可整理的独立副本。",
        "An original cannot also be replaced in the same organization.": "同一次整理中，原件不能同时作为待替换副本。",
        "The backup directory overlaps a selected skill.": "备份目录与所选技能目录重叠。",
        "Scan the skills before organizing them.": "请先扫描技能，再执行整理。",
        "The skill must be a local directory.": "请选择本机技能目录。",
        "Only real skill directories can be compared.": "仅比较实际存在的技能文件夹。",
        "The skill directory changed during inspection.": "技能目录在比较时发生变化，请重新扫描。",
        "The skill location changed during inspection.": "技能路径在比较时发生变化，请重新扫描。",
        "A directory changed during inspection.": "子目录在比较时发生变化，请重新扫描。",
        "A file changed during inspection.": "文件在比较时发生变化，请重新扫描。",
        "A file grew during inspection.": "文件在比较时增大，请重新扫描。",
        "A copy changed while it was being organized.": "副本在整理时发生变化。",
        "The backup directory must be local.": "备份目录必须位于本机。",
        "Choose a dedicated backup directory.": "请选择独立的备份目录。",
        "The backup path is unavailable or contains a symbolic link.": "备份路径不可用，或路径中含有软链接。",
        "The backup directory must belong to this user and must not be writable by other users.": "备份目录必须属于当前用户，且仅当前用户可写入。",
        "The organization lock is unsafe.": "整理锁文件的类型、所有者或权限不符合要求。",
        "Another organization is running.": "已有整理操作正在进行。",
        "The backup directory changed.": "备份目录已发生变化。",
        "Invalid organization record.": "整理记录无效。",
        "The organization record is too large.": "整理记录过大。",
        "The organization record is unsafe or too large.": "整理记录的文件属性不符合要求，或文件过大。",
        "The organization record changed while reading.": "整理记录在读取时发生变化。",
        "Invalid organization backup paths.": "整理记录中的备份路径无效。",
        "This organization has already been restored.": "这次整理已经撤销。",
        "A retained original was replaced.": "备份副本已被替换，无法恢复。",
        "A retained original was edited. It was left in the backup directory.": "备份副本已被编辑，仍保留在备份目录中。",
        "A pending original changed.": "待恢复的副本已发生变化。",
        "A retained original is missing.": "找不到备份副本。",
        "The installed link changed; the skill was left untouched.": "技能链接已变化，已保留现有技能。",
        "The installed link points to a different original.": "技能链接已指向其他原件。",
        "The installed link is missing; the retained original was left in the backup directory.": "技能链接已被移除，整理前的副本仍保留在备份目录中。",
        "A skill parent changed into a symbolic link.": "技能的上级目录已变成软链接。",
        "A skill parent was replaced.": "技能的上级目录已被替换。",
        "A filename is not valid UTF-8.": "文件名不是有效的 UTF-8 文本。",
        "A directory entry disappeared.": "目录中的项目已被移走或删除。",
        "A directory entry changed.": "目录中的项目已发生变化。"
    ]

    private static let actions: [String: String] = [
        "Create backup batch": "无法创建本次整理的备份",
        "Open backup batch": "无法打开本次整理的备份",
        "Stage skill link": "无法准备技能链接",
        "Save backup batch": "无法保存本次整理的备份",
        "Save retained original": "无法保存整理前的副本",
        "Save skill link": "无法保存技能链接",
        "Save skill backup": "无法保存技能备份",
        "Open skill parent": "无法打开技能的上级目录",
        "Open skill directory": "无法打开技能目录",
        "Open nested directory": "无法打开技能子目录",
        "Open skill file": "无法打开技能文件",
        "Read skill file": "无法读取技能文件",
        "Open backup path": "无法打开备份路径",
        "Create backup directory": "无法创建备份目录",
        "Open organization lock": "无法打开整理锁文件",
        "Open organization backup": "无法打开整理备份",
        "Create organization record": "无法创建整理记录",
        "Write organization record": "无法写入整理记录",
        "Save organization record": "无法保存整理记录",
        "Read organization record": "无法读取整理记录",
        "Save restored skill": "无法保存恢复的技能",
        "Open skill location": "无法打开技能所在目录",
        "Move skill without overwriting": "无法移动技能",
        "List skill directory": "无法列出技能目录",
        "Inspect file identity": "无法检查文件属性",
        "Inspect directory entry": "无法检查目录项目"
    ]
}
