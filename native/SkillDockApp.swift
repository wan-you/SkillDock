import SwiftUI
import AppKit
import Combine

private enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh_CN"
    case english = "en"
    var id: String { rawValue }
    var title: String { self == .simplifiedChinese ? "简体中文" : "English" }
    var locale: Locale { Locale(identifier: self == .simplifiedChinese ? "zh_CN" : "en_US") }
}

private enum L10n {
    static var current: AppLanguage = .simplifiedChinese

    static func text(_ simplifiedChinese: String, _ english: String) -> String {
        current == .simplifiedChinese ? simplifiedChinese : english
    }
}

private enum Palette {
    static let canvas = adaptive("canvas", light: (0.955, 0.963, 0.969), dark: (0.055, 0.065, 0.08))
    static let sidebar = adaptive("sidebar", light: (0.925, 0.942, 0.944), dark: (0.075, 0.087, 0.102))
    static let panel = adaptive("panel", light: (0.985, 0.990, 0.992), dark: (0.092, 0.106, 0.124))
    static let raised = adaptive("raised", light: (0.938, 0.950, 0.958), dark: (0.12, 0.137, 0.158))
    static let hover = adaptive("hover", light: (0.896, 0.924, 0.930), dark: (0.15, 0.17, 0.193))
    static let relationshipSurface = adaptive("relationshipSurface", light: (0.948, 0.978, 0.968), dark: (0.13, 0.175, 0.195))
    static let relationshipNode = adaptive("relationshipNode", light: (0.895, 0.937, 0.921), dark: (0.165, 0.215, 0.24))
    static let relationshipCurrent = adaptive("relationshipCurrent", light: (0.80, 0.91, 0.857), dark: (0.16, 0.285, 0.25))
    static let line = adaptive("line", light: (0.12, 0.20, 0.20), dark: (1, 1, 1), lightAlpha: 0.12, darkAlpha: 0.075)
    static let lineStrong = adaptive("lineStrong", light: (0.12, 0.20, 0.20), dark: (1, 1, 1), lightAlpha: 0.21, darkAlpha: 0.13)
    static let text = adaptive("text", light: (0.12, 0.17, 0.19), dark: (0.92, 0.94, 0.95))
    static let secondary = adaptive("secondary", light: (0.30, 0.36, 0.40), dark: (0.69, 0.73, 0.77))
    static let muted = adaptive("muted", light: (0.365, 0.415, 0.445), dark: (0.59, 0.63, 0.68))
    static let mint = adaptive("mint", light: (0.065, 0.43, 0.32), dark: (0.47, 0.83, 0.70))
    static let mintInk = adaptive("mintInk", light: (0.98, 1, 0.99), dark: (0.07, 0.15, 0.12))
    static let blue = adaptive("blue", light: (0.18, 0.40, 0.72), dark: (0.50, 0.69, 0.94))
    static let amber = adaptive("amber", light: (0.57, 0.36, 0.095), dark: (0.87, 0.69, 0.40))
    static let claude = adaptive("claude", light: (0.65, 0.34, 0.21), dark: (0.91, 0.63, 0.47))
    static let danger = adaptive("danger", light: (0.65, 0.18, 0.23), dark: (0.94, 0.52, 0.54))

    private static func adaptive(_ name: String, light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat), lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("SkillDock.\(name)"), dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let components = isDark ? dark : light
            return NSColor(srgbRed: components.0, green: components.1, blue: components.2, alpha: isDark ? darkAlpha : lightAlpha)
        }))
    }
}

private enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L10n.text("跟随系统", "System")
        case .light: L10n.text("浅色", "Light")
        case .dark: L10n.text("深色", "Dark")
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private enum AgentKind: String, CaseIterable, Identifiable {
    case codex, claude, deepseek, mirasim
    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Desktop"
        case .deepseek: "DeepSeek Harness"
        case .mirasim: "Mirasim"
        }
    }
    var subtitle: String {
        switch self {
        case .codex: "OpenAI"
        case .claude: "Anthropic"
        case .deepseek: "DeepSeek"
        case .mirasim: L10n.text("本地 Agent", "Local Agent")
        }
    }
    var symbol: String {
        switch self {
        case .codex: "hexagon"
        case .claude: "sparkle"
        case .deepseek: "waveform.path"
        case .mirasim: "circle.hexagongrid"
        }
    }
    var accent: Color {
        switch self {
        case .codex: Palette.mint
        case .claude: Palette.claude
        case .deepseek: Palette.blue
        case .mirasim: Palette.amber
        }
    }
    var preferredBundleID: String {
        switch self {
        case .codex: "com.openai.codex"
        case .claude: "com.anthropic.claudefordesktop"
        case .deepseek: "com.deepseek.dsh"
        case .mirasim: "ai.mirofish.mirasim"
        }
    }
    var bundleIDs: Set<String> {
        switch self {
        case .codex: ["com.openai.codex", "com.openai.chat"]
        case .claude: ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .deepseek: ["com.deepseek.dsh", "com.deepseek.harness"]
        case .mirasim: ["ai.mirofish.mirasim"]
        }
    }
    var skillDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch self {
        case .codex: home.appending(path: ".codex/skills", directoryHint: .isDirectory)
        case .claude: home.appending(path: ".claude/skills", directoryHint: .isDirectory)
        case .deepseek:
            if let customHome = ProcessInfo.processInfo.environment["DSH_HOME"], !customHome.isEmpty {
                URL(fileURLWithPath: customHome, isDirectory: true).appending(path: "skills", directoryHint: .isDirectory)
            } else {
                home.appending(path: ".dsh/skills", directoryHint: .isDirectory)
            }
        case .mirasim: home.appending(path: ".mirasim/skills", directoryHint: .isDirectory)
        }
    }
    var alternateSkillDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .codex: return []
        case .claude: return [home.appending(path: ".claude/skills/synced", directoryHint: .isDirectory)]
        case .deepseek: return []
        case .mirasim: return []
        }
    }
    var loadsSharedSkills: Bool { self == .codex || self == .deepseek || self == .mirasim }
}

private struct InstalledAgent: Identifiable, Hashable {
    let kind: AgentKind
    let applicationURL: URL
    let bundleIdentifier: String
    let applicationName: String
    var id: String { kind.id }

    var applicationIcon: NSImage {
        // Prefer the bundled full-resolution artwork where it is available.
        // DeepSeek's small ICNS layers decode incorrectly on macOS.
        if kind == .deepseek || kind == .mirasim,
           let image = NSImage(contentsOf: applicationURL.appending(path: "Contents/Resources/icon.png")) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}

private enum SkillOrigin: Hashable {
    case library
    case dotAgent
    case shared
    case archived
    case agent(AgentKind)
    case other

    var title: String {
        switch self {
        case .library: "SkillDock Library"
        case .dotAgent: L10n.text("全局 · ~/.agent", "Global · ~/.agent")
        case .shared: L10n.text("全局 · ~/.agents/skills", "Global · ~/.agents/skills")
        case .archived: L10n.text("归档 · ~/.agents/archived-skills", "Archived · ~/.agents/archived-skills")
        case .agent(let kind): kind.title
        case .other: L10n.text("其他本机目录", "Other local")
        }
    }

    var searchTerms: String {
        switch self {
        case .library: "技能库 library SkillDock Library"
        case .dotAgent: "全局 global ~/.agent"
        case .shared: "全局 共享 global shared ~/.agents/skills"
        case .archived: "归档 archived ~/.agents/archived-skills"
        case .agent(let kind): kind.title
        case .other: "其他 本机 other local"
        }
    }
}

private struct SkillItem: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let path: URL
    let origin: SkillOrigin
    let version: String?
    let skillCount: Int
    var isSymbolicLink: Bool
    var isManagedSync: Bool
    let aliases: [String]
    let upstreamReferences: [String]
    let downstreamReferences: [String]
    var defaultAgent: AgentKind? = nil
    var modifiedAt: Date = .distantPast
    var filesystemSnapshot: SkillFilesystemSnapshot? = nil

    var isDefault: Bool { defaultAgent != nil }
    var displayDescription: String { description.isEmpty ? L10n.text("可在本机分享的技能。", "Local skill available to share.") : description }
}

private struct SkillFilesystemSnapshot: Hashable {
    let item: SkillFileIdentity
    let parent: SkillFileIdentity
    let parentPath: String

    static func capture(at path: URL) -> SkillFilesystemSnapshot? {
        let lexicalPath = path.standardizedFileURL
        let parentPath = lexicalPath.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        guard let item = SkillFileIdentity.identity(at: lexicalPath),
              let parent = SkillFileIdentity.identity(at: parentPath), parent.isDirectory else { return nil }
        return SkillFilesystemSnapshot(item: item, parent: parent, parentPath: parentPath.path)
    }
}

private struct DefaultSkillSource {
    let root: URL
    let agent: AgentKind
    var allowedFolders: Set<String>? = nil
    var protectsWholeRoot = true

    var protectedRoots: [URL] {
        protectsWholeRoot ? [root] : (allowedFolders ?? []).map { root.appending(path: $0, directoryHint: .isDirectory) }
    }

    func contains(_ path: URL) -> Bool {
        let folder = path.resolvingSymlinksInPath().standardizedFileURL
        let directory = root.resolvingSymlinksInPath().standardizedFileURL
        guard folder.deletingLastPathComponent() == directory else { return false }
        return allowedFolders?.contains(folder.lastPathComponent) ?? true
    }
}

private enum DefaultSkillCatalog {
    static func sources(home: URL, agents: [InstalledAgent]) -> [DefaultSkillSource] {
        var sources = [DefaultSkillSource(root: home.appending(path: ".codex/skills/.system", directoryHint: .isDirectory), agent: .codex)]
        if let claude = claudeSource(home: home) { sources.append(claude) }
        if let mirasim = mirasimSource(home: home) { sources.append(mirasim) }
        if let deepseek = agents.first(where: { $0.kind == .deepseek }) {
            sources.append(DefaultSkillSource(root: deepseek.applicationURL.appending(path: "Contents/Resources/runtime/office-skills", directoryHint: .isDirectory), agent: .deepseek))
        }
        return sources
    }

    static func owner(of folder: URL, origin: SkillOrigin, sources: [DefaultSkillSource]) -> AgentKind? {
        guard case .agent(let kind) = origin else { return nil }
        return sources.first(where: { $0.agent == kind && $0.contains(folder) })?.agent
    }

    private static func mirasimSource(home: URL) -> DefaultSkillSource? {
        let root = home.appending(path: ".mirasim/skills", directoryHint: .isDirectory)
        let builtInNames = ["eval", "mirasim-guide", "mirasim-operate", "mirasim-publish"]
        let installed = Set(builtInNames.filter { name in
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            guard SkillFileIdentity.identity(at: folder)?.isDirectory == true,
                  let data = SkillFileSafety.completeManifest(at: folder.appending(path: ".mirasim-skill.json")),
                  let marker = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  marker["name"] as? String == name,
                  let fingerprint = marker["fingerprint"] as? String,
                  fingerprint.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return false }
            return true
        })
        guard !installed.isEmpty else { return nil }
        return DefaultSkillSource(root: root, agent: .mirasim, allowedFolders: installed, protectsWholeRoot: false)
    }

    private static func claudeSource(home: URL) -> DefaultSkillSource? {
        let fm = FileManager.default
        let cache = home.appending(path: "Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin", directoryHint: .isDirectory)
        func children(_ root: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        }
        var latest: (root: URL, updated: Double, skills: [[String: Any]])?
        // Claude keeps one generated plugin per local session/account. The
        // newest valid manifest is authoritative; its plugin also contains user
        // skills, so classification must use each entry's creatorType.
        for account in children(cache) {
            for session in children(account) {
                guard let data = SkillFileSafety.completeManifest(at: session.appending(path: "manifest.json")),
                      let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let updated = manifest["lastUpdated"] as? NSNumber,
                      let entries = manifest["skills"] as? [[String: Any]] else { continue }
                let root = session.appending(path: "skills", directoryHint: .isDirectory)
                guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if latest == nil || updated.doubleValue > latest!.updated {
                    latest = (root, updated.doubleValue, entries)
                }
            }
        }
        guard let latest else { return nil }
        let allowed = Set(latest.skills.compactMap { entry -> String? in
            guard entry["creatorType"] as? String == "anthropic",
                  let name = entry["name"] as? String, !name.isEmpty,
                  name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { return nil }
            return name
        })
        return DefaultSkillSource(root: latest.root, agent: .claude, allowedFolders: allowed)
    }
}

private enum SkillFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case global = "全局"
    case library = "Library"
    case agent = "Agent"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: L10n.text("全部", "All")
        case .global: L10n.text("全局", "Global")
        case .library: "Library"
        case .agent: "Agent"
        }
    }
}

private enum SkillSortOrder: String, CaseIterable, Identifiable {
    case nameAscending, nameDescending, source, recentlyModified
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nameAscending: L10n.text("名称 · A → Z", "Name · A → Z")
        case .nameDescending: L10n.text("名称 · Z → A", "Name · Z → A")
        case .source: L10n.text("按来源", "Source")
        case .recentlyModified: L10n.text("最近修改", "Recently modified")
        }
    }
}

private enum SkillPresentation {
    static func matches(_ skill: SkillItem, query: String) -> Bool {
        let tokens = normalize(query).split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let abbreviatedPath = skill.path.path.hasPrefix(home + "/")
            ? "~" + skill.path.path.dropFirst(home.count) : skill.path.path
        let type = skill.isDefault ? "自带 默认 default builtin built in" : "自定义 custom"
        let fields = [skill.name, skill.description, skill.origin.searchTerms, skill.path.path,
                      String(abbreviatedPath), skill.version ?? "", type,
                      skill.defaultAgent?.title ?? ""] + skill.aliases
        let searchable = normalize(fields.joined(separator: " "))
        return tokens.allSatisfy { searchable.contains($0) }
    }

    static func sorted(_ skills: [SkillItem], order: SkillSortOrder) -> [SkillItem] {
        skills.sorted { lhs, rhs in
            switch order {
            case .source:
                let lhsSource = originOrder(lhs.origin), rhsSource = originOrder(rhs.origin)
                if lhsSource != rhsSource { return lhsSource < rhsSource }
            case .recentlyModified:
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            case .nameAscending, .nameDescending: break
            }
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame {
                return order == .nameDescending ? nameOrder == .orderedDescending : nameOrder == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    static func originOrder(_ origin: SkillOrigin) -> Int {
        switch origin {
        case .library: 0
        case .dotAgent: 1
        case .shared: 2
        case .agent(.codex): 3
        case .agent(.claude): 4
        case .agent(.deepseek): 5
        case .agent(.mirasim): 6
        case .archived: 7
        case .other: 8
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

private struct SkillRelationNode: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
}

private struct SkillRelationships {
    var upstream: [SkillRelationNode] = []
    var downstream: [SkillRelationNode] = []
}

private struct SkillMetadata {
    var name: String?
    var description: String?
    var version: String?
    var aliases: [String] = []
    var upstreamReferences: [String] = []
    var downstreamReferences: [String] = []
}

private enum TransferMode: String, CaseIterable, Identifiable {
    case link = "Link"
    case copy = "Copy"
    var id: String { rawValue }
    var symbol: String { self == .link ? "link" : "doc.on.doc" }
    var title: String { self == .link ? L10n.text("链接", "Link") : L10n.text("复制", "Copy") }
}

private enum SkillOpenAvailability {
    case available, notInstalled, unsupported
}

@MainActor
private final class SkillStore: ObservableObject {
    @Published private(set) var agents: [InstalledAgent] = []
    @Published private(set) var skills: [SkillItem] = []
    @Published private(set) var openTargetAvailability: [SkillOpenTarget: SkillOpenAvailability] = [:]
    @Published private(set) var openingSkillIDs: Set<String> = []
    @Published var selectedAgentID: String?
    @Published var selectedSkillID: String?
    @Published var language: AppLanguage = .simplifiedChinese {
        didSet {
            L10n.current = language
            defaults.set(language.rawValue, forKey: "SkillDock.language")
            notice = nil
        }
    }
    @Published var searchText = ""
    @Published var sortOrder: SkillSortOrder = .nameAscending {
        didSet { defaults.set(sortOrder.rawValue, forKey: "SkillDock.sortOrder") }
    }
    @Published var filter: SkillFilter = .all
    @Published var transferMode: TransferMode = .link
    @Published var expandedDefaultAgents: Set<AgentKind> = []
    @Published var notice: Notice?
    @Published var lastScan = Date()
    private var timer: AnyCancellable?
    private let defaults: UserDefaults
    private var protectedSkillRoots: [URL] = []

    let libraryDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/SkillDock/Library", directoryHint: .isDirectory)
    let dotAgentPath = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agent", directoryHint: .isDirectory)
    let sharedDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agents/skills", directoryHint: .isDirectory)
    let archivedDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agents/archived-skills", directoryHint: .isDirectory)

    var dotAgentSkillDirectories: [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotAgentPath.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        // Some installations put skills directly in ~/.agent, while others use
        // ~/.agent/skills. Scan both locations when they coexist so neither
        // layout is silently omitted.
        var roots = [dotAgentPath]
        let nested = dotAgentPath.appending(path: "skills", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory), isDirectory.boolValue {
            roots.append(nested)
        }
        return roots
    }

    var dotAgentStatus: String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotAgentPath.path, isDirectory: &isDirectory) else { return L10n.text("未发现 ~/.agent", "~/.agent not found") }
        guard isDirectory.boolValue else { return L10n.text("~/.agent 是文件，不是技能目录", "~/.agent is a file, not a skills folder") }
        let nested = dotAgentPath.appending(path: "skills", directoryHint: .isDirectory)
        var nestedIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: nested.path, isDirectory: &nestedIsDirectory), nestedIsDirectory.boolValue {
            return L10n.text("已发现技能目录（根目录 + skills 子目录）", "Skills found in root and skills subfolder")
        }
        return L10n.text("已发现技能目录（根目录）", "Skills found in root folder")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "SkillDock.language") ?? "") ?? .simplifiedChinese
        L10n.current = language
        sortOrder = SkillSortOrder(rawValue: defaults.string(forKey: "SkillDock.sortOrder") ?? "") ?? .nameAscending
        refresh()
        if !isProtectedLocation(libraryDirectory) {
            try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        }
        selectedSkillID = skills.first(where: { $0.origin == .library })?.id ?? skills.first(where: { !$0.isDefault })?.id
        timer = Timer.publish(every: 12, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var selectedAgent: InstalledAgent? {
        agents.first(where: { $0.id == selectedAgentID }) ?? agents.first
    }

    var selectedSkill: SkillItem? {
        skills.first(where: { $0.id == selectedSkillID })
    }

    var filteredSkills: [SkillItem] {
        let matchingSkills = skills.filter { skill in
            let queryMatch = SkillPresentation.matches(skill, query: searchText)
            let filterMatch: Bool
            switch filter {
            case .all: filterMatch = true
            case .global: filterMatch = skill.origin == .dotAgent || skill.origin == .shared || skill.origin == .archived
            case .library: filterMatch = skill.origin == .library
            case .agent:
                if case .agent = skill.origin { filterMatch = true } else { filterMatch = false }
            }
            return queryMatch && filterMatch
        }
        return SkillPresentation.sorted(matchingSkills, order: sortOrder)
    }

    var selectedAgentSkills: [SkillItem] {
        guard let agent = selectedAgent else { return [] }
        return SkillPresentation.sorted(skills(for: agent.kind).filter {
            SkillPresentation.matches($0, query: searchText)
        }, order: sortOrder)
    }

    func defaultSkillsExpansion(for kind: AgentKind) -> Binding<Bool> {
        Binding(get: { self.expandedDefaultAgents.contains(kind) }, set: { expanded in
            if expanded { self.expandedDefaultAgents.insert(kind) }
            else { self.expandedDefaultAgents.remove(kind) }
        })
    }

    var globalSkillCount: Int {
        skills.filter { $0.origin == .dotAgent || $0.origin == .shared || $0.origin == .archived }.count
    }

    var dotAgentSkillCount: Int { skills.filter { $0.origin == .dotAgent }.count }
    var sharedSkillCount: Int { skills.filter { $0.origin == .shared }.count }
    var archivedSkillCount: Int { skills.filter { $0.origin == .archived }.count }

    func skills(for kind: AgentKind) -> [SkillItem] {
        let localRoots = [kind.skillDirectory] + kind.alternateSkillDirectories
        let localPaths = Set(localRoots.map { $0.standardizedFileURL.path })
        let sharedPath = sharedDirectory.standardizedFileURL.path
        let includesShared = kind.loadsSharedSkills
        let candidates = skills.filter { skill in
            let path = skill.path.standardizedFileURL.path
            let parent = skill.path.deletingLastPathComponent().standardizedFileURL.path
            return skill.defaultAgent == kind || localPaths.contains(parent) || (includesShared && (path == sharedPath || path.hasPrefix(sharedPath + "/")))
        }
        // Choose the local representation before applying the user's display
        // order, so changing sorting never swaps a link for its shared source.
        let preferredCandidates = candidates.filter {
            localPaths.contains($0.path.deletingLastPathComponent().standardizedFileURL.path)
        } + candidates.filter {
            !localPaths.contains($0.path.deletingLastPathComponent().standardizedFileURL.path)
        }
        var resolvedPaths = Set<String>()
        return preferredCandidates.filter { skill in
            resolvedPaths.insert(skill.path.resolvingSymlinksInPath().standardizedFileURL.path).inserted
        }
    }

    func refresh() {
        agents = discoverAgents()
        openTargetAvailability = Dictionary(uniqueKeysWithValues: SkillOpenTarget.allCases.map { target in
            guard let application = SkillOpenService.applicationURL(for: target) else {
                return (target, .notInstalled)
            }
            return (target, SkillOpenService.supportsFolderOpening(applicationURL: application) ? .available : .unsupported)
        })
        if selectedAgentID == nil || !agents.contains(where: { $0.id == selectedAgentID }) {
            selectedAgentID = agents.first?.id
        }
        skills = scanSkills()
        if let selectedSkillID, !skills.contains(where: { $0.id == selectedSkillID }) {
            self.selectedSkillID = nil
        }
        lastScan = Date()
    }

    func skillCount(for kind: AgentKind) -> Int { skills(for: kind).count }

    func openSkill(_ skill: SkillItem, in target: SkillOpenTarget) {
        guard openingSkillIDs.insert(skill.id).inserted else { return }
        Task {
            defer { openingSkillIDs.remove(skill.id) }
            do {
                let outcome = try await SkillOpenService.open(target: target, directory: skill.path)
                showNotice(L10n.text(outcome.chineseMessage, outcome.englishMessage), style: .success)
            } catch let error as SkillOpenError {
                showNotice(L10n.text(error.chineseMessage, error.englishMessage), style: .error)
            } catch {
                showNotice(L10n.text("无法打开技能：\(error.localizedDescription)", "Could not open skill: \(error.localizedDescription)"), style: .error)
            }
        }
    }

    func isInstalled(_ item: SkillItem, in kind: AgentKind) -> Bool {
        if item.defaultAgent == kind { return true }
        if item.origin == .shared && kind.loadsSharedSkills { return true }
        if kind.loadsSharedSkills {
            let sharedNamePath = sharedDirectory.appending(path: item.path.lastPathComponent, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: sharedNamePath.path) { return true }
        }
        let namePath = kind.skillDirectory.appending(path: item.path.lastPathComponent, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: namePath.path)
    }

    func transfer(_ skill: SkillItem, to kind: AgentKind, mode: TransferMode? = nil) {
        guard snapshotMatches(skill) else { showChangedSkillNotice(); return }
        let mode = mode ?? transferMode
        let destinationRoot = kind.skillDirectory
        let destination = destinationRoot.appending(path: skill.path.lastPathComponent, directoryHint: .isDirectory)
        let fm = FileManager.default
        do {
            guard writableDestinationRoot(destinationRoot) else { return }
            if isInstalled(skill, in: kind) {
                let sharedNamePath = sharedDirectory.appending(path: skill.path.lastPathComponent, directoryHint: .isDirectory)
                let alreadyShared = kind.loadsSharedSkills && fm.fileExists(atPath: sharedNamePath.path)
                let message = alreadyShared
                    ? L10n.text("\(skill.name) 已通过 Shared 对 \(kind.title) 可用", "\(skill.name) is available to \(kind.title) through Shared")
                    : L10n.text("\(skill.name) 已存在于 \(kind.title) 的技能目录", "\(skill.name) already exists in \(kind.title)’s skills folder")
                showNotice(message, style: .warning)
                return
            }
            try fm.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            guard writableDestinationRoot(destinationRoot) else { return }
            guard !fm.fileExists(atPath: destination.path) else {
                showNotice(L10n.text("\(skill.name) 已存在于 \(kind.title) 的技能目录", "\(skill.name) already exists in \(kind.title)’s skills folder"), style: .warning)
                return
            }
            switch mode {
            case .link:
                try fm.createSymbolicLink(at: destination, withDestinationURL: skill.path)
            case .copy:
                try fm.copyItem(at: skill.path, to: destination)
            }
            refresh()
            selectedAgentID = kind.id
            selectedSkillID = destination.path
            showNotice(mode == .link ? L10n.text("\(skill.name) 已链接到 \(kind.title)", "\(skill.name) was linked to \(kind.title)") : L10n.text("\(skill.name) 已复制到 \(kind.title)", "\(skill.name) was copied to \(kind.title)"), style: .success)
        } catch {
            showNotice(L10n.text("无法写入技能目录：\(error.localizedDescription)", "Could not write to the skills folder: \(error.localizedDescription)"), style: .error)
        }
    }

    func copyToLibrary(_ skill: SkillItem, mode: TransferMode = .copy) {
        guard snapshotMatches(skill) else { showChangedSkillNotice(); return }
        let destination = libraryDirectory.appending(path: skill.path.lastPathComponent, directoryHint: .isDirectory)
        let fm = FileManager.default
        do {
            guard writableDestinationRoot(libraryDirectory) else { return }
            try fm.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
            guard writableDestinationRoot(libraryDirectory) else { return }
            guard !fm.fileExists(atPath: destination.path) else {
                showNotice(L10n.text("\(skill.name) 已存在于 SkillDock Library", "\(skill.name) already exists in SkillDock Library"), style: .warning)
                return
            }
            switch mode {
            case .link: try fm.createSymbolicLink(at: destination, withDestinationURL: skill.path)
            case .copy: try fm.copyItem(at: skill.path, to: destination)
            }
            refresh()
            selectedSkillID = destination.path
            showNotice(L10n.text("\(skill.name) 已复制到 SkillDock Library", "\(skill.name) was copied to SkillDock Library"), style: .success)
        } catch {
            showNotice(L10n.text("无法更新 SkillDock Library：\(error.localizedDescription)", "Could not update SkillDock Library: \(error.localizedDescription)"), style: .error)
        }
    }

    @discardableResult
    func promoteToShared(_ skill: SkillItem) -> Bool {
        guard snapshotMatches(skill) else { showChangedSkillNotice(); return false }
        let fm = FileManager.default
        let source = skill.path.resolvingSymlinksInPath().standardizedFileURL
        let sharedRoot = SkillFileSafety.canonicalLocation(at: sharedDirectory)
        if skill.origin == .shared || source.path.hasPrefix(sharedRoot.path + "/") {
            showNotice(L10n.text("\(skill.name) 已是共享全局技能", "\(skill.name) is already a shared global skill"), style: .warning)
            return false
        }
        let destination = sharedDirectory.appending(path: skill.path.lastPathComponent, directoryHint: .isDirectory)
        // Stage an independent directory copy, including when the dragged item
        // is a leaf link. Only a completed copy receives its public skill name.
        let staging = sharedDirectory.appending(path: ".skilldock-\(UUID().uuidString)", directoryHint: .isDirectory)
        var stagingIdentity: SkillFileIdentity?
        defer {
            if let stagingIdentity, SkillFileIdentity.identity(at: staging) == stagingIdentity {
                try? fm.removeItem(at: staging)
            }
        }
        do {
            guard writableSharedRoot() else { return false }
            guard SkillFileIdentity.identity(at: source)?.isDirectory == true,
                  SkillFileSafety.metadataPrefix(at: source.appending(path: "SKILL.md")) != nil else {
                showNotice(L10n.text("无法将此来源设为全局技能，请检查技能目录", "This source cannot be made global. Check its skill folder."), style: .warning)
                return false
            }
            let containerRoots = manageableSkillRoots + (skill.isDefault ? [] : protectedSkillRoots)
            let sourceIsContainer = containerRoots.contains {
                SkillFileSafety.canonicalLocation(at: $0).path == source.path
            }
            guard !sourceIsContainer, sharedRoot.path != source.path, !sharedRoot.path.hasPrefix(source.path + "/") else {
                showNotice(L10n.text("技能来源与全局目录重叠，无法复制", "The source overlaps the global skills folder and cannot be copied."), style: .warning)
                return false
            }
            guard SkillFileIdentity.identity(at: destination) == nil else {
                showNotice(L10n.text("共享全局已有同名技能：\(skill.name)", "A shared global skill already has this name: \(skill.name)"), style: .warning)
                return false
            }
            try fm.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            guard writableSharedRoot(), snapshotMatches(skill),
                  SkillFileSafety.canonicalLocation(at: sharedDirectory).path == sharedRoot.path else {
                showChangedSkillNotice()
                return false
            }
            do {
                try fm.copyItem(at: source, to: staging)
            } catch {
                stagingIdentity = SkillFileIdentity.identity(at: staging)
                throw error
            }
            stagingIdentity = SkillFileIdentity.identity(at: staging)
            guard writableSharedRoot(), snapshotMatches(skill),
                  SkillFileSafety.canonicalLocation(at: sharedDirectory).path == sharedRoot.path else {
                showChangedSkillNotice()
                return false
            }
            guard SkillFileIdentity.identity(at: destination) == nil else {
                showNotice(L10n.text("共享全局已有同名技能：\(skill.name)", "A shared global skill already has this name: \(skill.name)"), style: .warning)
                return false
            }
            try fm.moveItem(at: staging, to: destination)
            refresh()
            selectedSkillID = destination.standardizedFileURL.path
            if filter == .agent || filter == .library {
                filter = .global
            }
            if let selectedSkill, !SkillPresentation.matches(selectedSkill, query: searchText) { searchText = "" }
            showNotice(L10n.text("\(skill.name) 已设为全局技能，原技能已保留", "\(skill.name) is now a global skill. The original was kept."), style: .success)
            return true
        } catch {
            showNotice(L10n.text("无法设为全局技能：\(error.localizedDescription)", "Could not make the skill global: \(error.localizedDescription)"), style: .error)
            return false
        }
    }

    private func writableSharedRoot() -> Bool {
        // Shared remains read-only to generic transfers and management actions.
        // Only this promotion path may add a new entry to its dedicated root.
        let shared = SkillFileSafety.canonicalLocation(at: sharedDirectory).path
        let otherRoots = protectedSkillRoots.filter { $0.standardizedFileURL != sharedDirectory.standardizedFileURL } + manageableSkillRoots
        let overlaps = otherRoots.contains {
            let other = SkillFileSafety.canonicalLocation(at: $0).path
            return shared == other || shared.hasPrefix(other + "/") || other.hasPrefix(shared + "/")
        }
        guard !overlaps else {
            showNotice(L10n.text("共享全局与其他技能目录重叠，无法写入", "Shared global overlaps another skill location and cannot be changed."), style: .warning)
            return false
        }
        return true
    }

    private var manageableSkillRoots: [URL] {
        var roots = [libraryDirectory]
        roots.append(contentsOf: dotAgentSkillDirectories)
        for kind in AgentKind.allCases {
            roots.append(kind.skillDirectory)
            roots.append(contentsOf: kind.alternateSkillDirectories)
        }
        roots.append(archivedDirectory)
        return roots.map { $0.standardizedFileURL }
    }

    private func directSkillRoot(for skill: SkillItem) -> URL? {
        let path = skill.path.standardizedFileURL
        let parent = path.deletingLastPathComponent().standardizedFileURL
        guard path.lastPathComponent != "." && path.lastPathComponent != "..",
              !manageableSkillRoots.contains(path) else { return nil }
        return manageableSkillRoots.first(where: { $0 == parent })
    }

    private func isLocalOrigin(_ origin: SkillOrigin) -> Bool {
        switch origin {
        case .library, .dotAgent, .archived, .agent: return true
        case .shared, .other: return false
        }
    }

    private func snapshotMatches(_ skill: SkillItem) -> Bool {
        guard let snapshot = skill.filesystemSnapshot,
              let current = SkillFilesystemSnapshot.capture(at: skill.path) else { return false }
        return snapshot == current
    }

    private func isProtectedLocation(_ url: URL) -> Bool {
        let candidate = SkillFileSafety.canonicalLocation(at: url).path
        return protectedSkillRoots.contains { root in
            let protectedPath = SkillFileSafety.canonicalLocation(at: root).path
            return candidate == protectedPath || candidate.hasPrefix(protectedPath + "/")
        }
    }

    private func managedSkillState(for skill: SkillItem) -> SkillFilesystemSnapshot? {
        guard isLocalOrigin(skill.origin), directSkillRoot(for: skill) != nil,
              let scanned = skill.filesystemSnapshot,
              let live = SkillFilesystemSnapshot.capture(at: skill.path), scanned == live,
              live.item.isDirectory || live.item.isSymbolicLink,
              !isProtectedLocation(URL(fileURLWithPath: live.parentPath, isDirectory: true)) else { return nil }
        // A leaf link can be unlinked, while a root alias must retain the
        // read-only policy of the directory it points into.
        if !live.item.isSymbolicLink && isProtectedLocation(skill.path) { return nil }
        return live
    }

    private func showChangedSkillNotice() {
        showNotice(L10n.text("技能目录已变化，请重新扫描后再操作", "The skill folder has changed. Rescan before trying again."), style: .warning)
    }

    private func writableDestinationRoot(_ root: URL) -> Bool {
        guard !isProtectedLocation(root) else {
            showNotice(L10n.text("目标目录指向只读技能来源，无法写入", "The destination points to a read-only skill source and cannot be changed."), style: .warning)
            return false
        }
        return true
    }

    func canArchive(_ skill: SkillItem) -> Bool {
        guard isLocalOrigin(skill.origin), skill.origin != .archived,
              !skill.isSymbolicLink, !skill.isManagedSync, !skill.isDefault else { return false }
        return managedSkillState(for: skill)?.item.isDirectory == true
    }

    func canDelete(_ skill: SkillItem) -> Bool {
        guard isLocalOrigin(skill.origin), skill.origin != .shared,
              !skill.isManagedSync, !skill.isDefault else { return false }
        return managedSkillState(for: skill) != nil
    }

    func managementHint(for skill: SkillItem) -> String {
        if skill.isDefault { return L10n.text("这是 Agent 自带的默认技能，由 Agent 管理；可以复制到 Library 后单独管理。", "This built-in skill is managed by its Agent. Copy it to Library to manage an independent version.") }
        if skill.origin == .shared { return L10n.text("Shared 技能供 Codex / DeepSeek / Mirasim 读取，请先复制到 Library。", "Shared skills are available to Codex / DeepSeek / Mirasim. Copy this skill to Library to manage it.") }
        if skill.isManagedSync { return L10n.text("Claude synced 技能由 Claude 管理，不能在这里改动。", "Claude manages its synced skills. They are read-only here.") }
        if !isLocalOrigin(skill.origin) || directSkillRoot(for: skill) == nil || managedSkillState(for: skill) == nil {
            return L10n.text("此来源只读，不能在这里归档或删除。", "This source is read-only and cannot be archived or deleted here.")
        }
        if skill.origin == .archived { return L10n.text("这是归档技能，可以永久删除。", "This archived skill can be permanently deleted.") }
        if skill.isSymbolicLink { return L10n.text("这是 Agent 中的链接，只能删除链接，不能归档源目录。", "This is a link in an Agent folder. You can remove the link; its source cannot be archived here.") }
        return ""
    }

    func archive(_ skill: SkillItem) {
        guard snapshotMatches(skill) else { showChangedSkillNotice(); return }
        guard canArchive(skill) else {
            showNotice(L10n.text("该技能来源不支持归档", "This skill source cannot be archived"), style: .warning)
            return
        }
        let fm = FileManager.default
        let destination = archivedDirectory.appending(path: skill.path.lastPathComponent, directoryHint: .isDirectory)
        do {
            guard writableDestinationRoot(archivedDirectory) else { return }
            try fm.createDirectory(at: archivedDirectory, withIntermediateDirectories: true)
            guard writableDestinationRoot(archivedDirectory) else { return }
            guard !fm.fileExists(atPath: destination.path) else {
                showNotice(L10n.text("归档区已有同名技能：\(skill.name)", "An archived skill already has this name: \(skill.name)"), style: .warning)
                return
            }
            try fm.moveItem(at: skill.path, to: destination)
            refresh()
            selectedSkillID = destination.standardizedFileURL.path
            showNotice(L10n.text("\(skill.name) 已归档到 ~/.agents/archived-skills", "\(skill.name) was archived to ~/.agents/archived-skills"), style: .success)
        } catch {
            showNotice(L10n.text("归档失败：\(error.localizedDescription)", "Could not archive the skill: \(error.localizedDescription)"), style: .error)
        }
    }

    func delete(_ skill: SkillItem) {
        guard snapshotMatches(skill) else { showChangedSkillNotice(); return }
        guard canDelete(skill) else {
            showNotice(L10n.text("该技能来源不支持删除", "This skill source cannot be deleted"), style: .warning)
            return
        }
        let wasLink = skill.isSymbolicLink
        do {
            // The path is intentionally kept lexical: removing an Agent link
            // unlinks the link itself and never follows it to the source.
            try FileManager.default.removeItem(at: skill.path.standardizedFileURL)
            if selectedSkillID == skill.id { selectedSkillID = nil }
            refresh()
            showNotice(wasLink ? L10n.text("已移除 Agent 中的技能链接", "The skill link was removed from the Agent folder") : L10n.text("\(skill.name) 已永久删除", "\(skill.name) was permanently deleted"), style: .success)
        } catch {
            showNotice(L10n.text("删除失败：\(error.localizedDescription)", "Could not delete the skill: \(error.localizedDescription)"), style: .error)
        }
    }

    func relationships(for skill: SkillItem) -> SkillRelationships {
        let currentCanonical = canonicalPath(skill.path)
        var upstream: [SkillRelationNode] = []
        var downstream: [SkillRelationNode] = []
        var upstreamIDs = Set<String>()
        var downstreamIDs = Set<String>()
        let aliasMap = makeAliasMap()

        func addUpstream(_ item: SkillItem) {
            guard item.id != skill.id, upstreamIDs.insert(item.id).inserted else { return }
            upstream.append(relationNode(for: item, symbol: "arrow.right"))
        }
        func addDownstream(_ item: SkillItem) {
            guard item.id != skill.id, downstreamIDs.insert(item.id).inserted else { return }
            downstream.append(relationNode(for: item, symbol: "arrow.right"))
        }
        func addDownstreamAgent(_ kind: AgentKind, detail: String? = nil) {
            let id = "agent:\(kind.id)"
            guard downstreamIDs.insert(id).inserted else { return }
            downstream.append(SkillRelationNode(id: id, title: kind.title, detail: detail ?? shortPath(kind.skillDirectory), symbol: "arrow.right"))
        }

        // A symbolic link is a real source → destination relationship. Copies remain independent.
        if skill.isSymbolicLink {
            for candidate in skills where !candidate.isSymbolicLink && canonicalPath(candidate.path) == currentCanonical { addUpstream(candidate) }
        }
        for candidate in skills where candidate.isSymbolicLink && canonicalPath(candidate.path) == currentCanonical { addDownstream(candidate) }

        for reference in skill.upstreamReferences {
            for target in resolve(reference, using: aliasMap) { addUpstream(target) }
        }
        for reference in skill.downstreamReferences {
            for target in resolve(reference, using: aliasMap) { addDownstream(target) }
        }
        for candidate in skills where candidate.id != skill.id {
            if candidate.upstreamReferences.contains(where: { resolve($0, using: aliasMap).contains(where: { $0.id == skill.id }) }) { addDownstream(candidate) }
            if candidate.downstreamReferences.contains(where: { resolve($0, using: aliasMap).contains(where: { $0.id == skill.id }) }) { addUpstream(candidate) }
        }

        // These agents can use skills directly from ~/.agents/skills.
        if skill.origin == .shared {
            for agent in agents where agent.kind.loadsSharedSkills { addDownstreamAgent(agent.kind) }
        }
        if let owner = skill.defaultAgent, agents.contains(where: { $0.kind == owner }) {
            addDownstreamAgent(owner, detail: L10n.text("自带默认技能", "Built-in skill"))
        }
        return SkillRelationships(upstream: upstream.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }, downstream: downstream.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
    }

    private func canonicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    private func normalizedSkillKey(_ value: String) -> String {
        var key = value.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        if key.hasSuffix("/skill.md") { key = String(key.dropLast("/skill.md".count)) }
        key = key.replacingOccurrences(of: "\\", with: "/")
        key = key.split(separator: "/").last.map(String.init) ?? key
        return key.replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
    }

    private func makeAliasMap() -> [String: [SkillItem]] {
        var map: [String: [SkillItem]] = [:]
        for item in skills {
            let keys = [item.name, item.path.lastPathComponent] + item.aliases
            for key in keys {
                let normalized = normalizedSkillKey(key)
                guard !normalized.isEmpty else { continue }
                map[normalized, default: []].append(item)
            }
        }
        return map
    }

    private func resolve(_ reference: String, using map: [String: [SkillItem]]) -> [SkillItem] {
        let matches = map[normalizedSkillKey(reference)] ?? []
        let unique = Dictionary(grouping: matches, by: { canonicalPath($0.path) }).compactMap { $0.value.first }
        return unique.count == 1 ? unique : []
    }

    private func relationNode(for item: SkillItem, symbol: String) -> SkillRelationNode {
        SkillRelationNode(id: "skill:\(item.id)", title: item.name, detail: "\(item.origin.title) · \(shortPath(item.path))", symbol: symbol)
    }

    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    func remove(_ skill: SkillItem) {
        delete(skill)
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func showNotice(_ message: String, style: Notice.Style) {
        withAnimation(.snappy(duration: 0.24)) { notice = Notice(message: message, style: style) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.4))
            withAnimation(.snappy(duration: 0.22)) { self?.notice = nil }
        }
    }

    private func discoverAgents() -> [InstalledAgent] {
        let fm = FileManager.default
        let searchRoots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                           fm.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)]
        var bundles: [(AgentKind, URL, String, String)] = []
        for root in searchRoots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for appURL in children where appURL.pathExtension == "app" {
                guard let bundle = Bundle(url: appURL) else { continue }
                let bundleID = (bundle.bundleIdentifier ?? "").lowercased()
                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent
                for kind in AgentKind.allCases where kind.bundleIDs.contains(bundleID) || appURL.lastPathComponent.localizedLowercase.contains(kind.title.localizedLowercase) {
                    bundles.append((kind, appURL, bundleID, displayName))
                }
            }
        }
        for kind in AgentKind.allCases {
            for identifier in kind.bundleIDs {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                      !bundles.contains(where: { $0.1.standardizedFileURL == appURL.standardizedFileURL }),
                      let bundle = Bundle(url: appURL) else { continue }
                let bundleID = (bundle.bundleIdentifier ?? identifier).lowercased()
                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent
                bundles.append((kind, appURL, bundleID, displayName))
            }
        }
        let unique = AgentKind.allCases.compactMap { kind -> InstalledAgent? in
            let matches = bundles.filter { $0.0 == kind }
            let exact = matches.first(where: { $0.2 == kind.preferredBundleID })
                ?? matches.first(where: { kind.bundleIDs.contains($0.2) })
            let fallback = matches.first(where: { candidate in
                let name = candidate.1.deletingPathExtension().lastPathComponent.localizedLowercase
                return name == kind.title.localizedLowercase || name == kind.title.replacingOccurrences(of: " ", with: "").localizedLowercase
            })
            guard let found = exact ?? fallback else { return nil }
            return InstalledAgent(kind: kind, applicationURL: found.1, bundleIdentifier: found.2, applicationName: found.3)
        }
        return AgentKind.allCases.compactMap { kind in unique.first(where: { $0.kind == kind }) }
    }

    private func scanSkills() -> [SkillItem] {
        let fm = FileManager.default
        let defaults = DefaultSkillCatalog.sources(home: fm.homeDirectoryForCurrentUser, agents: agents)
        var roots: [(URL, SkillOrigin)] = [(libraryDirectory, .library)]
        roots.append(contentsOf: dotAgentSkillDirectories.map { ($0, .dotAgent) })
        roots.append((sharedDirectory, .shared))
        roots.append((archivedDirectory, .archived))
        for kind in AgentKind.allCases {
            roots.append((kind.skillDirectory, .agent(kind)))
            roots.append(contentsOf: kind.alternateSkillDirectories.map { ($0, .agent(kind)) })
        }
        let home = fm.homeDirectoryForCurrentUser
        let additional = [
            home.appending(path: ".codex/vendor_imports/skills", directoryHint: .isDirectory),
            home.appending(path: ".deepseek/skills", directoryHint: .isDirectory)
        ]
        roots.append(contentsOf: additional.map { ($0, .other) })
        roots.append(contentsOf: defaults.map { ($0.root, .agent($0.agent)) })
        protectedSkillRoots = [sharedDirectory,
            AgentKind.claude.skillDirectory.appending(path: "synced", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin", directoryHint: .isDirectory)]
            + additional + defaults.flatMap { $0.protectedRoots }

        var results: [SkillItem] = []
        var seen = Set<String>()
        for (root, origin) in roots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
            for folder in children {
                if let source = defaults.first(where: { $0.protectsWholeRoot && $0.root.standardizedFileURL == root.standardizedFileURL }),
                   let allowed = source.allowedFolders, !allowed.contains(folder.lastPathComponent) { continue }
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                let resolved = folder.resolvingSymlinksInPath().standardizedFileURL
                let identity = folder.standardizedFileURL.path
                guard seen.insert(identity).inserted else { continue }
                let skillFile = resolved.appending(path: "SKILL.md")
                guard fm.fileExists(atPath: skillFile.path) else { continue }
                let parsed = parseSkillMetadata(at: skillFile)
                let modifiedAt = (try? skillFile.resolvingSymlinksInPath().resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let relativeName = parsed.name ?? folder.lastPathComponent
                let name = relativeName.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                let count = (try? fm.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).count) ?? 1
                guard let snapshot = SkillFilesystemSnapshot.capture(at: folder),
                      snapshot.item.isDirectory || snapshot.item.isSymbolicLink else { continue }
                let syncedRoot = AgentKind.claude.skillDirectory.appending(path: "synced", directoryHint: .isDirectory).standardizedFileURL.path
                let managedSync = origin == .agent(.claude) && identity.hasPrefix(syncedRoot + "/")
                results.append(SkillItem(id: folder.standardizedFileURL.path, name: name, description: parsed.description ?? "", path: folder, origin: origin, version: parsed.version, skillCount: count, isSymbolicLink: snapshot.item.isSymbolicLink, isManagedSync: managedSync, aliases: parsed.aliases, upstreamReferences: parsed.upstreamReferences, downstreamReferences: parsed.downstreamReferences, defaultAgent: DefaultSkillCatalog.owner(of: folder, origin: origin, sources: defaults), modifiedAt: modifiedAt, filesystemSnapshot: snapshot))
            }
        }
        return SkillPresentation.sorted(results, order: .source)
    }

    private func parseSkillMetadata(at file: URL) -> SkillMetadata {
        guard let data = SkillFileSafety.metadataPrefix(at: file) else { return SkillMetadata() }
        let text = String(decoding: data, as: UTF8.self)
        var metadata = SkillMetadata()
        var inFrontmatter = false
        var sawOpening = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(120) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                if !sawOpening { sawOpening = true; inFrontmatter = true; continue }
                if inFrontmatter { break }
            }
            guard inFrontmatter, let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            switch key {
            case "name": metadata.name = value
            case "description": metadata.description = value
            case "version": metadata.version = value
            case "alias", "aliases": metadata.aliases.append(contentsOf: parseList(value))
            case "dependencies", "depends_on", "requires", "upstream": metadata.upstreamReferences.append(contentsOf: parseList(value))
            case "downstream": metadata.downstreamReferences.append(contentsOf: parseList(value))
            default: break
            }
        }
        return metadata
    }

    private func parseList(_ value: String) -> [String] {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return cleaned.split(separator: ",").map { token in
            String(token).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }.filter { !$0.isEmpty }
    }

}

private struct Notice: Identifiable {
    enum Style { case success, warning, error }
    let id = UUID()
    let message: String
    let style: Style
}

@main
struct SkillDockApp: App {
    @StateObject private var store = SkillStore()
    var body: some Scene {
        WindowGroup("SkillDock") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1280, minHeight: 720)
                .background(Palette.canvas)
        }
        .defaultSize(width: 1420, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(L10n.text("重新扫描 Agent 与技能", "Rescan Agents and Skills")) { store.refresh() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var store: SkillStore
    @State private var showSettings = false
    @StateObject private var relationshipPresentation = RelationshipPresentation()
    @AppStorage("SkillDock.appearance") private var appearance: AppAppearance = .dark
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                agentSidebar
                    .frame(width: 226)
                Rectangle().fill(Palette.line).frame(width: 1)
                sourcePanel
                    .frame(width: 338)
                Rectangle().fill(Palette.line).frame(width: 1)
                destinationPanel
                    .frame(maxWidth: .infinity)
                Rectangle().fill(Palette.line).frame(width: 1)
                inspectorPanel
                    .frame(width: 286)
            }
        }
        .background(Palette.canvas)
        .preferredColorScheme(appearance.preferredColorScheme)
        .tint(Palette.mint)
        .overlayPreferenceValue(RelationshipAnchorKey.self) { anchors in
            RelationshipOverlay(anchors: anchors)
        }
        .coordinateSpace(name: RelationshipCoordinateSpace.window)
        .environmentObject(relationshipPresentation)
        .onExitCommand {
            if relationshipPresentation.selection != nil { relationshipPresentation.dismiss() }
            else if !store.searchText.isEmpty { store.searchText = "" }
            else { searchFocused = false }
        }
        .overlay(alignment: .bottomTrailing) {
            if let notice = store.notice { NoticeToast(notice: notice).padding(22).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.snappy(duration: 0.22), value: store.notice?.id)
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(store) }
        .environment(\.locale, store.language.locale)
    }

    private var titleBar: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Palette.mint).frame(width: 29, height: 29)
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.mintInk)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("SkillDock").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Palette.text)
                Text(L10n.text("本机技能管理", "LOCAL SKILL MANAGEMENT")).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.15).foregroundStyle(Palette.muted)
            }
            searchField.frame(width: 280)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Palette.mint).frame(width: 6, height: 6)
                Text(L10n.text("\(store.agents.count) 个 Agent", "\(store.agents.count) Agents")).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            .help(L10n.text("自动检测已开启，每 12 秒扫描", "Auto-detection enabled; scans every 12 seconds"))
            Button { store.refresh(); store.showNotice(L10n.text("已重新扫描本机 Agent 与技能目录", "Rescanned local Agents and skills folders"), style: .success) } label: {
                Label(L10n.text("重新扫描", "Rescan"), systemImage: "arrow.clockwise").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(QuietButtonStyle())
            Menu {
                Picker(L10n.text("外观", "Appearance"), selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.inline).labelsHidden()
            } label: {
                Label(L10n.text("外观", "Appearance"), systemImage: appearance.symbol)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L10n.text("切换浅色、深色或跟随系统", "Choose light, dark, or system appearance"))
            .accessibilityLabel(L10n.text("切换外观", "Change appearance"))
            Menu {
                Picker(L10n.text("语言", "Language"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                .pickerStyle(.inline).labelsHidden()
            } label: {
                Label(L10n.text("语言", "Language"), systemImage: "character.bubble")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(L10n.text("切换简体中文或英语", "Choose Simplified Chinese or English"))
            .accessibilityLabel(L10n.text("切换语言", "Change language"))
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(IconButtonStyle())
                .help(L10n.text("扫描设置", "Scan settings"))
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
        .background(Palette.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Button { searchFocused = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
            .help(L10n.text("搜索技能（⌘F）", "Search skills (⌘F)"))
            TextField(L10n.text("搜索技能、路径、Agent", "Search skills, paths, Agents"), text: $store.searchText)
                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.text)
                .focused($searchFocused)
            if !store.searchText.isEmpty {
                Button { store.searchText = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain).help(L10n.text("清除搜索", "Clear search"))
            } else if !searchFocused {
                Text("⌘F").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 10).frame(height: 38)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(searchFocused ? Palette.mint.opacity(0.6) : Palette.lineStrong, lineWidth: 1))
        .help(L10n.text("搜索名称、说明、别名、来源或路径；多个词同时匹配", "Search names, descriptions, aliases, sources, or paths; all words must match"))
    }

    private var agentSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("检测到的 Agent", "Detected Agents")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 14)).foregroundStyle(Palette.mint)
            }
            .padding(.horizontal, 15).padding(.top, 22).padding(.bottom, 11)

            if store.agents.isEmpty {
                ContentUnavailableView(L10n.text("未发现 Agent", "No Agents found"), systemImage: "app.dashed", description: Text(L10n.text("安装 Codex、Claude Desktop、DeepSeek Harness 或 Mirasim 后，重新扫描即可。", "Install Codex, Claude Desktop, DeepSeek Harness, or Mirasim, then rescan.")))
                    .padding(12).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(store.agents) { agent in
                            AgentSidebarRow(agent: agent, selected: store.selectedAgent?.id == agent.id, skillCount: store.skillCount(for: agent.kind)) {
                                withAnimation(.snappy(duration: 0.23)) { store.selectedAgentID = agent.id; store.selectedSkillID = nil }
                            }
                        }
                    }
                    .padding(.horizontal, 9)
                }
                .frame(minHeight: 60, maxHeight: .infinity)
            }

            Spacer().frame(height: 20)
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("技能目录", "SKILL LOCATIONS")).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.1).foregroundStyle(Palette.muted)
                PathRow(symbol: "square.stack.3d.up", label: "Library", path: "~/Library/.../SkillDock/Library", onDrop: { id in
                    guard let skill = store.skills.first(where: { $0.id == id }) else { return false }
                    store.copyToLibrary(skill)
                    return true
                })
                PathRow(symbol: "globe.americas.fill", label: L10n.text("共享全局", "Shared global"), path: L10n.text("~/.agents/skills · \(store.sharedSkillCount) 个", "~/.agents/skills · \(store.sharedSkillCount)"), onDrop: { id in
                    guard let skill = store.skills.first(where: { $0.id == id }) else { return false }
                    return store.promoteToShared(skill)
                })
                .help(L10n.text("拖入技能设为全局：复制到 ~/.agents/skills 并保留原技能", "Drop a skill to make it global: copy to ~/.agents/skills and keep the original"))
                HStack(spacing: 7) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 13)).foregroundStyle(Palette.amber).frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("~/.agent").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                        HStack(spacing: 4) {
                            Text(store.dotAgentStatus).font(.system(size: 11)).foregroundStyle(Palette.amber)
                            if store.dotAgentSkillCount > 0 {
                                Text(L10n.text("· \(store.dotAgentSkillCount) 个技能", "· \(store.dotAgentSkillCount) skills")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    Spacer()
                }
                PathRow(symbol: "archivebox", label: L10n.text("归档", "Archived"), path: L10n.text("~/.agents/archived-skills · \(store.archivedSkillCount) 个", "~/.agents/archived-skills · \(store.archivedSkillCount)"), onDrop: { id in
                    guard let skill = store.skills.first(where: { $0.id == id }) else { return false }
                    guard store.canArchive(skill) else {
                        store.showNotice(L10n.text("Shared、链接或受 Agent 管理的技能不能直接归档", "Shared, linked, and Agent-managed skills cannot be archived directly"), style: .warning)
                        return false
                    }
                    store.archive(skill)
                    return true
                })
                if let agent = store.selectedAgent { PathRow(symbol: agent.kind.symbol, label: agent.kind.title, path: "~" + agent.kind.skillDirectory.path.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count)) }
                Text(L10n.text("拖到共享全局设为全局技能；拖到 Library 收纳，拖到 Agent 分配。", "Drag to Shared global to make skills global, to Library to collect them, or to an Agent to assign them."))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 3)
            }
            .padding(13)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
            .padding(11)

            HStack(spacing: 7) {
                Image(systemName: "externaldrive.fill").font(.system(size: 13)).foregroundStyle(Palette.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("此 Mac", "This Mac")).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
                    Text(L10n.text("自动每 12 秒扫描", "Auto-scan every 12 seconds")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Circle().fill(Palette.mint).frame(width: 6, height: 6)
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
        .background(Palette.sidebar)
    }

    private var sourcePanel: some View {
        let matchingSkills = store.filteredSkills
        let searching = !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let regularSkills = searching ? matchingSkills : matchingSkills.filter { !$0.isDefault }
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("技能来源", "Skill Sources")).font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.text)
                        Text(L10n.text("技能库与本机 Agent", "LIBRARY & LOCAL AGENTS")).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Text("\(store.filteredSkills.count)").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Palette.secondary).padding(.horizontal, 7).padding(.vertical, 4).background(Palette.raised, in: Capsule())
                }
                Text(L10n.text("全局 \(store.globalSkillCount) · Shared \(store.sharedSkillCount) · 归档 \(store.archivedSkillCount) · ~/.agent \(store.dotAgentSkillCount)", "Global \(store.globalSkillCount) · Shared \(store.sharedSkillCount) · Archived \(store.archivedSkillCount) · ~/.agent \(store.dotAgentSkillCount)"))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Picker(L10n.text("技能来源", "Skill Sources"), selection: $store.filter) {
                    ForEach(SkillFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.regular).labelsHidden().id(store.language)
                HStack {
                    Text(searching ? L10n.text("搜索结果", "Search results") : L10n.text("技能列表", "Skills")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                    SkillSortMenu()
                }
            }
            .padding(16)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }

            if store.filteredSkills.isEmpty {
                ContentUnavailableView(L10n.text("没有匹配的技能", "No matching skills"), systemImage: searching ? "magnifyingglass" : "square.stack.3d.up", description: Text(searching ? L10n.text("尝试技能名称、说明、别名或路径。", "Try a skill name, description, alias, or path.") : L10n.text("扫描到的 SKILL.md 技能会显示在这里。", "Skills detected by their SKILL.md files will appear here.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        if !searching {
                            ForEach(AgentKind.allCases) { kind in
                                let defaults = matchingSkills.filter { $0.defaultAgent == kind }
                                if !defaults.isEmpty {
                                    DefaultSkillsSection(title: L10n.text("\(kind.title) 默认技能", "\(kind.title) built-in skills"), count: defaults.count, isExpanded: store.defaultSkillsExpansion(for: kind)) {
                                        ForEach(defaults) { sourceSkillRow($0) }
                                    }
                                }
                            }
                        }
                        ForEach(regularSkills) { sourceSkillRow($0) }
                    }
                    .padding(9)
                }
                .scrollIndicators(.visible)
                .transformAnchorPreference(key: RelationshipAnchorKey.self, value: .bounds) { anchors, viewport in
                    anchors.viewports[.source] = viewport
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "info.circle").foregroundStyle(Palette.muted)
                Text(L10n.text("技能通过 SKILL.md 识别 · Codex / DeepSeek / Mirasim 可用 Shared", "Skills use SKILL.md · Shared is available to Codex / DeepSeek / Mirasim")).foregroundStyle(Palette.muted)
                Spacer()
                Button { store.reveal(store.libraryDirectory) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(IconButtonStyle()).help(L10n.text("在 Finder 中打开 SkillDock Library", "Show SkillDock Library in Finder"))
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
        .background(Palette.panel)
    }

    private func sourceSkillRow(_ skill: SkillItem) -> some View {
        SkillSourceRow(skill: skill, selected: store.selectedSkillID == skill.id) {
            withAnimation(.snappy(duration: 0.22)) { store.selectedSkillID = skill.id }
        }
    }

    private var destinationPanel: some View {
        VStack(spacing: 0) {
            if let agent = store.selectedAgent {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(agent.kind.accent.opacity(0.13)).frame(width: 40, height: 40)
                        Image(nsImage: agent.applicationIcon).resizable().interpolation(.high).scaledToFit().frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(agent.kind.title).font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        }
                        HStack(spacing: 7) {
                            Text(L10n.text("已检测", "Detected")).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.mint).padding(.horizontal, 6).padding(.vertical, 3).background(Palette.mint.opacity(0.1), in: Capsule())
                            Text(agent.applicationURL.path).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(store.skillCount(for: agent.kind))").font(.system(size: 23, weight: .semibold, design: .rounded)).foregroundStyle(Palette.text)
                        Text(L10n.text("已安装技能", "Installed skills")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.horizontal, 21).padding(.vertical, 17)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.text("\(agent.kind.title) 技能", "\(agent.kind.title) skills")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        Spacer()
                        Picker(L10n.text("分享方式", "Transfer mode"), selection: $store.transferMode) {
                            ForEach(TransferMode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                        }
                        .pickerStyle(.segmented).controlSize(.regular).labelsHidden().id(store.language).frame(width: 130)
                    }
                    Text(L10n.text("拖入左侧技能，按需链接或复制到本地目录", "Drag a skill from the left to link or copy it locally")).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    HStack {
                        Text(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.text("已安装列表", "Installed skills") : L10n.text("\(store.selectedAgentSkills.count) 项匹配结果", "\(store.selectedAgentSkills.count) matches"))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Spacer()
                        SkillSortMenu()
                    }
                }
                .padding(.horizontal, 19).padding(.top, 16).padding(.bottom, 12)

                AgentDropArea(agent: agent, skills: store.selectedAgentSkills, selectedSkillID: store.selectedSkillID, onSelect: { store.selectedSkillID = $0 }, onDrop: { id in
                    guard let skill = store.skills.first(where: { $0.id == id }) else { return false }
                    store.transfer(skill, to: agent.kind)
                    return true
                }, onOpen: { store.reveal($0) }, onRemove: { store.remove($0) })
                    .environmentObject(store)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)

                HStack(spacing: 7) {
                    Image(systemName: store.transferMode.symbol).foregroundStyle(Palette.mint)
                    Text(store.transferMode == .link ? L10n.text("共享链接会跟随源技能更新", "Linked skills follow updates to the source") : L10n.text("复制后会在目标 Agent 目录独立保存", "Copies are stored independently in the Agent folder")).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button { store.reveal(agent.kind.skillDirectory) } label: { Label(L10n.text("打开目录", "Open folder"), systemImage: "folder") }
                        .buttonStyle(QuietButtonStyle())
                }
                .font(.system(size: 12))
                .padding(.horizontal, 17).padding(.vertical, 11)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            } else {
                ContentUnavailableView(L10n.text("选择一个 Agent", "Select an Agent"), systemImage: "app.dashed", description: Text(L10n.text("安装的 Agent 会在扫描后出现在左侧。", "Installed Agents appear on the left after scanning.")))
            }
        }
        .background(Palette.canvas)
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("技能详情", "Skill Details")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted)
                Spacer()
                if let skill = store.selectedSkill {
                    SkillOpenMenu(skill: skill, compact: true).fixedSize()
                    Button { store.selectedSkillID = nil } label: { Image(systemName: "xmark") }.buttonStyle(IconButtonStyle()).help(L10n.text("清除选择", "Clear selection"))
                }
            }
            .padding(.horizontal, 15).padding(.top, 17).padding(.bottom, 13)

            if let skill = store.selectedSkill {
                SkillInspector(skill: skill)
                    .environmentObject(store)
            } else {
                VStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15).fill(Palette.panel).frame(width: 58, height: 58)
                        Image(systemName: "cursorarrow.and.square.on.square.dashed").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.muted)
                    }
                    Text(L10n.text("选择一个技能", "Select a skill")).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.secondary)
                    Text(L10n.text("在技能列表中点选，查看来源路径、说明和共享操作。", "Select a skill to see its source path, description, and sharing options."))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 195)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(Palette.mint).frame(width: 5, height: 5)
                Text(L10n.text("最近扫描 \(store.lastScan.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(store.language.locale)))", "Last scan \(store.lastScan.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(store.language.locale)))"))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
        .background(Palette.sidebar)
    }
}

private struct SkillSortMenu: View {
    @EnvironmentObject private var store: SkillStore

    var body: some View {
        Menu {
            Picker(L10n.text("排序方式", "Sort order"), selection: $store.sortOrder) {
                ForEach(SkillSortOrder.allCases) { order in Text(order.title).tag(order) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            Label(store.sortOrder.title, systemImage: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help(L10n.text("切换技能列表排序方式", "Change skill list sort order"))
        .accessibilityLabel(L10n.text("排序方式：\(store.sortOrder.title)", "Sort order: \(store.sortOrder.title)"))
    }
}

private struct AgentSidebarRow: View {
    @EnvironmentObject private var store: SkillStore
    @State private var isTargeted = false
    let agent: InstalledAgent
    let selected: Bool
    let skillCount: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: agent.applicationIcon)
                    .resizable().interpolation(.high).scaledToFit().frame(width: 29, height: 29).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.kind.title).font(.system(size: 13, weight: selected ? .semibold : .medium)).foregroundStyle(selected ? Palette.text : Palette.secondary)
                    Text(L10n.text("\(skillCount) 个技能 · \(agent.kind.subtitle)", "\(skillCount) skills · \(agent.kind.subtitle)")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Circle().fill(selected ? Palette.mint : Palette.muted.opacity(0.6)).frame(width: 5, height: 5)
            }
            .padding(.horizontal, 9).frame(height: 60)
            .background((isTargeted ? agent.kind.accent.opacity(0.18) : selected ? agent.kind.accent.opacity(0.10) : Color.clear), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isTargeted ? agent.kind.accent.opacity(0.65) : selected ? agent.kind.accent.opacity(0.22) : Color.clear, lineWidth: isTargeted ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first, let skill = store.skills.first(where: { $0.id == id }) else { return false }
            store.transfer(skill, to: agent.kind)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.snappy(duration: 0.2), value: isTargeted)
    }
}

private struct PathRow: View {
    @State private var isTargeted = false
    let symbol: String
    let label: String
    let path: String
    var onDrop: ((String) -> Bool)? = nil
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Palette.mint).frame(width: 14)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            Text(path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 4).padding(.vertical, onDrop == nil ? 3 : 7)
        .background(isTargeted ? Palette.mint.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isTargeted ? Palette.mint.opacity(0.65) : Color.clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: String.self) { items, _ in
            guard let onDrop, let id = items.first else { return false }
            return onDrop(id)
        } isTargeted: { isTargeted = $0 && onDrop != nil }
        .animation(.snappy(duration: 0.18), value: isTargeted)
    }
}

private struct DefaultSkillsSection<Content: View>: View {
    @Environment(\.locale) private var locale
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    let content: () -> Content

    init(title: String, count: Int, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        let _ = locale
        VStack(spacing: 5) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 13)).foregroundStyle(Palette.blue)
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 3)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Palette.canvas, in: Capsule())
                }
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.lineStrong, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(L10n.text("Agent 自带的默认技能，点击展开或收起", "Built-in Agent skills; click to expand or collapse"))
            .accessibilityLabel(L10n.text("\(title)，\(count) 个", "\(title), \(count) skills"))
            .accessibilityValue(isExpanded ? L10n.text("已展开", "Expanded") : L10n.text("已收起", "Collapsed"))
            if isExpanded { content() }
        }
    }
}

private struct SkillSourceRow: View {
    @Environment(\.locale) private var locale
    let skill: SkillItem
    let selected: Bool
    let action: () -> Void
    var body: some View {
        let _ = locale
        HStack(alignment: .top, spacing: 7) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(originColor.opacity(0.12)).frame(width: 31, height: 31)
                        Image(systemName: skill.isSymbolicLink ? "link" : "doc.text.fill").font(.system(size: 15, weight: .regular)).foregroundStyle(originColor)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(skill.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                            if skill.isSymbolicLink { Image(systemName: "link").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                            Spacer(minLength: 0)
                        }
                        Text(skill.displayDescription).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
                        HStack(spacing: 4) {
                            Text((skill.isDefault ? L10n.text("自带默认 · ", "Built-in · ") : "") + skill.origin.title.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.55).foregroundStyle(originColor).lineLimit(1).truncationMode(.middle)
                            if let version = skill.version { Text("· v\(version)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .draggable(skill.id) { DragPreview(skill: skill) }
            RelationshipTrigger(skill: skill, viewport: .source)
        }
        .padding(9)
        .background(selected ? Palette.mint.opacity(0.085) : Palette.sidebar.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Palette.mint.opacity(0.20) : Palette.line.opacity(0.8), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu { SkillOpenMenuItems(skill: skill, includeFinder: true) }
    }
    private var originColor: Color {
        switch skill.origin {
        case .library: Palette.mint
        case .dotAgent: Palette.amber
        case .shared: Palette.blue
        case .archived: Palette.muted
        case .agent(.claude): Palette.claude
        case .agent(.deepseek): Palette.blue
        case .agent(.codex): Palette.mint
        case .agent(.mirasim): Palette.amber
        case .other: Palette.secondary
        }
    }
}

private enum RelationshipCoordinateSpace {
    static let window = "skilldock-relationship-window"
}

private enum RelationshipViewport: Hashable {
    case source, destination
}

private struct RelationshipAnchors {
    var triggers: [UUID: Anchor<CGRect>] = [:]
    var viewports: [RelationshipViewport: Anchor<CGRect>] = [:]
}

private struct RelationshipAnchorKey: PreferenceKey {
    static var defaultValue = RelationshipAnchors()

    static func reduce(value: inout RelationshipAnchors, nextValue: () -> RelationshipAnchors) {
        let next = nextValue()
        value.triggers.merge(next.triggers) { _, new in new }
        value.viewports.merge(next.viewports) { _, new in new }
    }
}

@MainActor
private final class RelationshipPresentation: ObservableObject {
    struct Selection {
        let triggerID: UUID
        let skill: SkillItem
        let viewport: RelationshipViewport
    }

    @Published private(set) var selection: Selection?
    private var hoveringTriggerID: UUID?
    private var hoveringPanel = false
    private var dismissWorkItem: DispatchWorkItem?

    func show(_ skill: SkillItem, triggerID: UUID, viewport: RelationshipViewport) {
        cancelDismiss()
        if selection?.triggerID != triggerID {
            hoveringPanel = false
            selection = Selection(triggerID: triggerID, skill: skill, viewport: viewport)
        }
    }

    func triggerHover(_ hovering: Bool, skill: SkillItem, triggerID: UUID, viewport: RelationshipViewport) {
        if hovering {
            hoveringTriggerID = triggerID
            show(skill, triggerID: triggerID, viewport: viewport)
        } else if hoveringTriggerID == triggerID {
            hoveringTriggerID = nil
            scheduleDismiss(triggerID: triggerID)
        }
    }

    func panelHover(_ hovering: Bool, triggerID: UUID) {
        guard selection?.triggerID == triggerID else { return }
        hoveringPanel = hovering
        if hovering { cancelDismiss() } else { scheduleDismiss(triggerID: triggerID) }
    }

    func dismiss(triggerID: UUID? = nil) {
        guard triggerID == nil || selection?.triggerID == triggerID else { return }
        cancelDismiss()
        hoveringTriggerID = nil
        hoveringPanel = false
        selection = nil
    }

    private func cancelDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func scheduleDismiss(triggerID: UUID) {
        guard selection?.triggerID == triggerID else { return }
        cancelDismiss()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.selection?.triggerID == triggerID,
                  self.hoveringTriggerID != triggerID, !self.hoveringPanel else { return }
            self.dismiss(triggerID: triggerID)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
    }
}

private struct RelationshipTrigger: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var presentation: RelationshipPresentation
    let skill: SkillItem
    let viewport: RelationshipViewport
    // A skill can appear in both columns; each button owns a distinct anchor.
    @State private var triggerID = UUID()

    private var isPresented: Bool { presentation.selection?.triggerID == triggerID }

    var body: some View {
        let _ = locale
        Button { presentation.show(skill, triggerID: triggerID, viewport: viewport) } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isPresented ? Palette.mint : Palette.muted)
                .frame(width: 28, height: 28)
                .background(isPresented ? Palette.mint.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("查看技能上下游关系", "Show upstream and downstream skill relationships"))
        .onHover { hovering in
            presentation.triggerHover(hovering, skill: skill, triggerID: triggerID, viewport: viewport)
        }
        .frame(width: 28, height: 28)
        .anchorPreference(key: RelationshipAnchorKey.self, value: .bounds) {
            RelationshipAnchors(triggers: isPresented ? [triggerID: $0] : [:])
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onDisappear { presentation.dismiss(triggerID: triggerID) }
    }
}

private struct RelationshipOverlay: View {
    @EnvironmentObject private var store: SkillStore
    @EnvironmentObject private var presentation: RelationshipPresentation
    let anchors: RelationshipAnchors

    var body: some View {
        GeometryReader { geometry in
            if let selection = presentation.selection,
               let triggerAnchor = anchors.triggers[selection.triggerID],
               let viewportAnchor = anchors.viewports[selection.viewport] {
                let trigger = geometry[triggerAnchor]
                let viewport = geometry[viewportAnchor]
                let visible = viewport.intersects(trigger)
                Group {
                    if visible {
                        RelationshipPopoverLayout(trigger: trigger) {
                            SkillRelationshipPopover(skill: selection.skill, relationships: store.relationships(for: selection.skill), triggerY: trigger.midY)
                                .onHover { presentation.panelHover($0, triggerID: selection.triggerID) }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .transition(.identity)
                    }
                }
                .onChange(of: visible, initial: true) { _, visible in
                    if !visible { presentation.dismiss(triggerID: selection.triggerID) }
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

private struct RelationshipPopoverLayout: Layout {
    let trigger: CGRect
    static let width: CGFloat = 320
    static let topInset: CGFloat = 78
    static let bottomInset: CGFloat = 16
    static let horizontalInset: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    static func frame(trigger: CGRect, panelSize: CGSize, containerSize: CGSize) -> CGRect {
        let maxX = max(horizontalInset, containerSize.width - panelSize.width - horizontalInset)
        let maxY = max(topInset, containerSize.height - panelSize.height - bottomInset)
        return CGRect(
            x: min(max(horizontalInset, trigger.minX - panelSize.width - 2), maxX),
            y: min(max(topInset, trigger.midY - panelSize.height / 2), maxY),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let panel = subviews.first else { return }
        let availableHeight = max(1, bounds.height - Self.topInset - Self.bottomInset)
        let panelProposal = ProposedViewSize(width: Self.width, height: availableHeight)
        let size = panel.sizeThatFits(panelProposal)
        let frame = Self.frame(trigger: trigger, panelSize: size, containerSize: bounds.size)
        panel.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
}

private struct RelationshipPanelChrome: View {
    let triggerY: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let tailY = triggerY.map { $0 - geometry.frame(in: .named(RelationshipCoordinateSpace.window)).minY }
            let shape = RelationshipPanelShape(tailY: tailY)
            shape.fill(Palette.relationshipSurface)
                .overlay(shape.stroke(Palette.mint.opacity(0.55), lineWidth: 1))
        }
    }
}

private struct SkillRelationshipPopover: View {
    @Environment(\.locale) private var locale
    let skill: SkillItem
    let relationships: SkillRelationships
    var triggerY: CGFloat? = nil

    var body: some View {
        let _ = locale
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) { content }
                .scrollIndicators(.visible)
        }
        .frame(width: RelationshipPopoverLayout.width)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(RelationshipPanelChrome(triggerY: triggerY))
        .compositingGroup()
        .shadow(color: .black.opacity(0.48), radius: 16, x: 0, y: 7)
        .shadow(color: Palette.mint.opacity(0.12), radius: 5, x: 0, y: 0)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.mint)
                    .frame(width: 29, height: 29)
                    .background(Palette.relationshipCurrent, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("技能关系", "Skill Relationships")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(L10n.text("箭头表示来源 → 去向", "Arrows show source → destination")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }

            Rectangle().fill(Palette.mint.opacity(0.22)).frame(height: 1)

            RelationshipGroup(title: L10n.text("上游来源", "Upstream sources"), direction: L10n.text("上游 → 当前技能", "Upstream → this skill"), emptyMessage: L10n.text("暂无显式上游", "No explicit upstream source"), nodes: relationships.upstream, tint: Palette.blue)

            HStack(spacing: 8) {
                Rectangle().fill(Palette.mint).frame(width: 2, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(skill.origin.title).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.mint)
                }
                Spacer()
            }
            .padding(9)
            .background(Palette.relationshipCurrent, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.mint.opacity(0.4), lineWidth: 1))

            RelationshipGroup(title: L10n.text("下游使用", "Downstream use"), direction: L10n.text("当前技能 → 下游", "This skill → downstream"), emptyMessage: L10n.text("尚未分配给 Agent", "Not assigned to an Agent"), nodes: relationships.downstream, tint: Palette.amber)
        }
        .padding(14)
        .padding(.trailing, 8)
        .frame(width: RelationshipPopoverLayout.width, alignment: .leading)
    }
}

private struct RelationshipPanelShape: Shape {
    var tailY: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 12
        let right = rect.maxX - 8
        let arrowY = min(max(rect.minY + 24, tailY ?? rect.midY), rect.maxY - 24)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: right - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + radius), control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: arrowY - 8))
        path.addLine(to: CGPoint(x: rect.maxX, y: arrowY))
        path.addLine(to: CGPoint(x: right, y: arrowY + 8))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct RelationshipGroup: View {
    @Environment(\.locale) private var locale
    let title: String
    let direction: String
    let emptyMessage: String
    let nodes: [SkillRelationNode]
    let tint: Color

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(0.8).foregroundStyle(Palette.muted)
                Spacer(minLength: 5)
                Text(direction).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(tint.opacity(0.9))
            }
            if nodes.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "minus").foregroundStyle(Palette.muted)
                    Text(emptyMessage).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            } else {
                ForEach(nodes) { node in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: node.symbol.isEmpty ? "arrow.right" : node.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary).lineLimit(1)
                            Text(node.detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(7)
                    .background(Palette.relationshipNode, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }
}

private struct DragPreview: View {
    let skill: SkillItem
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill").foregroundStyle(Palette.mint)
            Text(skill.name).font(.system(size: 14, weight: .medium))
        }
        .padding(9).background(Palette.raised, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AgentDropArea: View {
    @EnvironmentObject private var store: SkillStore
    let agent: InstalledAgent
    let skills: [SkillItem]
    let selectedSkillID: String?
    let onSelect: (String) -> Void
    let onDrop: (String) -> Bool
    let onOpen: (URL) -> Void
    let onRemove: (SkillItem) -> Void
    @State private var isTargeted = false
    @State private var skillToRemove: SkillItem?

    private var isSearching: Bool { !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var defaultSkills: [SkillItem] { isSearching ? [] : skills.filter { $0.isDefault } }
    private var regularSkills: [SkillItem] { isSearching ? skills : skills.filter { !$0.isDefault } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: store.transferMode.symbol).font(.system(size: 13)).foregroundStyle(Palette.mint)
                Text(L10n.text("目标目录", "Folder")).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                Text("~" + agent.kind.skillDirectory.path.dropFirst(FileManager.default.homeDirectoryForCurrentUser.path.count))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(isTargeted ? (store.transferMode == .link ? L10n.text("释放以创建链接", "Release to link") : L10n.text("释放以复制技能", "Release to copy")) : L10n.text("拖入技能", "DROP SKILLS HERE"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(isTargeted ? Palette.mint : Palette.muted)
            }
            .padding(.horizontal, 12).frame(minHeight: 42)
            .background(Palette.canvas.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))

            if skills.isEmpty {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Palette.mint.opacity(0.08)).frame(width: 50, height: 50)
                        Image(systemName: isSearching ? "magnifyingglass" : "arrow.down.doc").font(.system(size: 23, weight: .light)).foregroundStyle(Palette.mint)
                    }
                    Text(isSearching ? L10n.text("没有匹配的技能", "No matching skills") : L10n.text("把技能拖到这里", "Drop skills here")).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.secondary)
                    Text(isSearching ? L10n.text("尝试技能名称、说明、别名或路径。", "Try a skill name, description, alias, or path.") : L10n.text("从左侧拖入 Library、Shared 或其他 Agent 的技能。\n\(agent.kind.title) 的技能目录会自动创建。", "Drag skills from Library, Shared, or another Agent.\nThe \(agent.kind.title) skills folder will be created automatically."))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(3)
                    if isSearching {
                        Button(L10n.text("清除搜索", "Clear search")) { store.searchText = "" }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        if !defaultSkills.isEmpty {
                            DefaultSkillsSection(title: L10n.text("自带默认技能", "Built-in skills"), count: defaultSkills.count, isExpanded: store.defaultSkillsExpansion(for: agent.kind)) {
                                ForEach(defaultSkills) { installedRow($0) }
                            }
                        }
                        ForEach(regularSkills) { installedRow($0) }
                    }
                    .padding(.vertical, 9)
                }
                .transformAnchorPreference(key: RelationshipAnchorKey.self, value: .bounds) { anchors, viewport in
                    anchors.viewports[.destination] = viewport
                }
            }
        }
        .padding(9)
        .background(isTargeted ? Palette.mint.opacity(0.045) : Palette.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(isTargeted ? Palette.mint.opacity(0.72) : Palette.lineStrong, style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: isTargeted ? [] : [5, 4])))
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            return onDrop(id)
        } isTargeted: { isTargeted = $0 }
        .alert(L10n.text("移除技能？", "Remove skill?"), isPresented: Binding(get: { skillToRemove != nil }, set: { if !$0 { skillToRemove = nil } })) {
            Button(L10n.text("取消", "Cancel"), role: .cancel) { skillToRemove = nil }
            Button(L10n.text("移除", "Remove"), role: .destructive) { if let skillToRemove { onRemove(skillToRemove) }; skillToRemove = nil }
        } message: {
            if let skill = skillToRemove {
                Text(skill.isSymbolicLink
                     ? L10n.text("将从 \(agent.kind.title) 的技能目录移除这个链接，源技能目录不会被删除。", "This link will be removed from \(agent.kind.title)’s skills folder. The source folder will remain.")
                     : L10n.text("将从 \(agent.kind.title) 的技能目录永久删除这个技能目录。", "This skill folder will be permanently deleted from \(agent.kind.title)."))
            } else {
                Text("")
            }
        }
    }

    private func installedRow(_ skill: SkillItem) -> some View {
        InstalledSkillRow(skill: skill, selected: selectedSkillID == skill.id, onSelect: { onSelect(skill.id) }, onOpen: { onOpen(skill.path) }, onRemove: store.canDelete(skill) ? { skillToRemove = skill } : nil)
    }
}

private struct InstalledSkillRow: View {
    @EnvironmentObject private var store: SkillStore
    let skill: SkillItem
    let selected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRemove: (() -> Void)?
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 9) {
            Button(action: onSelect) {
                HStack(spacing: 9) {
                    Image(systemName: skill.isSymbolicLink ? "link" : "doc.text.fill").font(.system(size: 15)).foregroundStyle(Palette.mint).frame(width: 28, height: 28).background(Palette.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(skill.isSymbolicLink ? L10n.text("链接自 \(skill.origin.title)", "Linked from \(skill.origin.title)") : skill.path.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .draggable(skill.id) { DragPreview(skill: skill) }
            RelationshipTrigger(skill: skill, viewport: .destination)
            ZStack(alignment: .trailing) {
                if hovering {
                    HStack(spacing: 9) {
                        Button(action: onOpen) { Image(systemName: "folder") }.buttonStyle(IconButtonStyle()).help(L10n.text("在 Finder 中显示", "Show in Finder"))
                        if let onRemove { Button(action: onRemove) { Image(systemName: "minus.circle") }.buttonStyle(IconButtonStyle()).help(L10n.text("从该 Agent 移除", "Remove from this Agent")) }
                    }
                } else if skill.isDefault {
                    Text(L10n.text("默认", "DEFAULT")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.blue).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.blue.opacity(0.09), in: Capsule())
                } else if skill.isManagedSync {
                    Text(L10n.text("同步", "SYNCED")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.blue).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.blue.opacity(0.09), in: Capsule())
                } else if skill.origin == .library {
                    Text(L10n.text("技能库", "LIBRARY")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.mint).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.mint.opacity(0.09), in: Capsule())
                } else if skill.origin == .shared {
                    Text(L10n.text("共享", "SHARED")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.blue).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.blue.opacity(0.09), in: Capsule())
                } else if skill.origin == .dotAgent {
                    Text(L10n.text("全局", "GLOBAL")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.amber).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.amber.opacity(0.09), in: Capsule())
                } else if skill.origin == .archived {
                    Text(L10n.text("归档", "ARCHIVED")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.muted).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.muted.opacity(0.09), in: Capsule())
                } else if skill.isSymbolicLink {
                    Text(L10n.text("链接", "LINK")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.mint).padding(.horizontal, 6).padding(.vertical, 4).background(Palette.mint.opacity(0.09), in: Capsule())
                }
            }
            // Keep the relationship anchor still during the hand-off to its panel.
            .frame(width: 72, height: 30, alignment: .trailing)
        }
        .padding(.horizontal, 8).frame(height: 60)
        .background(selected ? Palette.mint.opacity(0.07) : Palette.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Palette.mint.opacity(0.18) : Palette.line.opacity(0.8), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .contextMenu { SkillOpenMenuItems(skill: skill, includeFinder: true) }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.16), value: hovering)
    }
}

private struct SkillOpenMenuItems: View {
    @EnvironmentObject private var store: SkillStore
    let skill: SkillItem
    var includeFinder = false

    var body: some View {
        if includeFinder {
            Button { store.reveal(skill.path) } label: {
                Label(L10n.text("在 Finder 中查看", "Show in Finder"), systemImage: "folder")
            }
            Divider()
        }
        ForEach(SkillOpenTarget.allCases) { target in
            let availability = store.openTargetAvailability[target] ?? .notInstalled
            Button { store.openSkill(skill, in: target) } label: {
                Label(title(for: target, availability: availability), systemImage: target.symbol)
            }
            .disabled(availability != .available || store.openingSkillIDs.contains(skill.id))
        }
    }

    private func title(for target: SkillOpenTarget, availability: SkillOpenAvailability) -> String {
        let title = L10n.text(target.chineseTitle, target.englishTitle)
        switch availability {
        case .available: return title
        case .notInstalled: return title + L10n.text("（未安装）", " (not installed)")
        case .unsupported: return title + L10n.text("（需更新应用）", " (update required)")
        }
    }
}

private struct SkillOpenMenu: View {
    @EnvironmentObject private var store: SkillStore
    let skill: SkillItem
    var compact = false

    var body: some View {
        Menu { SkillOpenMenuItems(skill: skill) } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app")
                Text(store.openingSkillIDs.contains(skill.id)
                     ? L10n.text("正在打开…", "Opening…")
                     : (compact ? L10n.text("打开", "Open") : L10n.text("打开技能", "Open Skill")))
                if !compact { Spacer(minLength: 0) }
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 10).frame(height: compact ? 30 : 36)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.lineStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .disabled(store.openingSkillIDs.contains(skill.id))
        .help(L10n.text("在终端、VS Code、Codex 或 Claude Desktop 中打开技能目录", "Open the skill folder in Terminal, VS Code, Codex, or Claude Desktop"))
    }
}

private struct SkillInspector: View {
    @EnvironmentObject private var store: SkillStore
    let skill: SkillItem
    @State private var managementPrompt: SkillManagementPrompt?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Palette.mint.opacity(0.12)).frame(width: 52, height: 52)
                    Image(systemName: skill.isSymbolicLink ? "link" : "doc.text.fill").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.mint)
                }
                .padding(.top, 2)
                Text(skill.name).font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.text).padding(.top, 13)
                Text(skill.displayDescription).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.top, 7)

                HStack(spacing: 6) {
                    Label(skill.origin.title, systemImage: (skill.origin == .library || skill.origin == .dotAgent || skill.origin == .shared || skill.origin == .archived) ? "globe" : "app")
                    if let version = skill.version { Text("v\(version)") }
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.mint)
                .padding(.top, 12)

                HStack(spacing: 7) {
                    Button { if let agent = store.selectedAgent { store.transfer(skill, to: agent.kind, mode: .link) } } label: { Label(L10n.text("链接", "Link"), systemImage: "link") }
                        .buttonStyle(AccentButtonStyle()).disabled(store.selectedAgent == nil || store.isInstalled(skill, in: store.selectedAgent!.kind))
                    Button { if let agent = store.selectedAgent { store.transfer(skill, to: agent.kind, mode: .copy) } } label: { Label(L10n.text("复制", "Copy"), systemImage: "doc.on.doc") }
                        .buttonStyle(SecondaryButtonStyle()).disabled(store.selectedAgent == nil || store.isInstalled(skill, in: store.selectedAgent!.kind))
                }
                .padding(.top, 16)

                Divider().overlay(Palette.line).padding(.vertical, 17)
                InspectorField(title: L10n.text("来源路径", "SOURCE PATH"), value: skill.path.path, mono: true, copy: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(skill.path.path, forType: .string); store.showNotice(L10n.text("路径已复制", "Path copied"), style: .success) })
                InspectorField(title: L10n.text("技能文件", "SKILL FILE"), value: "SKILL.md", mono: true, copy: { store.reveal(skill.path.appending(path: "SKILL.md")) })
                    .padding(.top, 14)
                InspectorField(title: L10n.text("目录内容", "CONTENTS"), value: L10n.text("\(skill.skillCount) 个项目", "\(skill.skillCount) items"), mono: false, copy: nil).padding(.top, 14)

                Divider().overlay(Palette.line).padding(.vertical, 17)
                Text(L10n.text("分享动作", "Sharing")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                VStack(spacing: 9) {
                    TransferOption(symbol: "link", title: L10n.text("创建链接", "Create a link"), detail: L10n.text("目标 Agent 引用同一份技能文件", "The target Agent uses the same skill files"), selected: store.transferMode == .link) { store.transferMode = .link }
                    TransferOption(symbol: "doc.on.doc", title: L10n.text("复制独立副本", "Create a copy"), detail: L10n.text("复制目录，之后可以单独编辑", "Copy the folder to edit it independently"), selected: store.transferMode == .copy) { store.transferMode = .copy }
                }
                .padding(.top, 10)

                if skill.origin != .library {
                    Divider().overlay(Palette.line).padding(.vertical, 17)
                    Button { store.copyToLibrary(skill) } label: {
                        Label(L10n.text("复制到 SkillDock Library", "Copy to SkillDock Library"), systemImage: "globe.badge.plus").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Button { store.reveal(skill.path) } label: {
                    Label(L10n.text("在 Finder 中查看", "Show in Finder"), systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(QuietButtonStyle()).padding(.top, 12)

                Divider().overlay(Palette.line).padding(.vertical, 17)
                Text(L10n.text("管理技能", "Manage Skill")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                if store.canArchive(skill) || store.canDelete(skill) {
                    HStack(spacing: 7) {
                        if store.canArchive(skill) {
                            Button { managementPrompt = .archive } label: {
                                Label(L10n.text("归档", "Archive"), systemImage: "archivebox")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        if store.canDelete(skill) {
                            Button(role: .destructive) { managementPrompt = .delete } label: {
                                Label(L10n.text("删除", "Delete"), systemImage: "trash")
                            }
                            .buttonStyle(DangerButtonStyle())
                        }
                    }
                    .padding(.top, 9)
                } else {
                    Text(store.managementHint(for: skill))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 15)
            .padding(.bottom, 20)
        }
        // Keep management confirmations behind one alert item. SwiftUI only presents
        // one alert per view hierarchy reliably; two boolean alerts can race when the
        // inspector is reused for a newly selected skill.
        .alert(item: $managementPrompt) { prompt in
            switch prompt {
            case .archive:
                return Alert(
                    title: Text(L10n.text("归档技能？", "Archive skill?")),
                    message: Text(L10n.text("将“\(skill.name)”移动到 ~/.agents/archived-skills。现有 Agent 链接可能因此失效。", "Move “\(skill.name)” to ~/.agents/archived-skills. Existing Agent links may stop working.")),
                    primaryButton: .cancel(Text(L10n.text("取消", "Cancel"))),
                    secondaryButton: .default(Text(L10n.text("归档", "Archive"))) { store.archive(skill) }
                )
            case .delete:
                return Alert(
                    title: Text(L10n.text("永久删除技能？", "Permanently delete skill?")),
                    message: Text(skill.isSymbolicLink ? L10n.text("只会移除 Agent 中的链接，源技能目录不会被删除。", "Only the link in the Agent folder will be removed. The source folder will remain.") : L10n.text("将永久删除“\(skill.name)”的技能目录，此操作无法撤销。", "Permanently delete the “\(skill.name)” folder. This cannot be undone.")),
                    primaryButton: .cancel(Text(L10n.text("取消", "Cancel"))),
                    secondaryButton: .destructive(Text(L10n.text("永久删除", "Delete permanently"))) { store.delete(skill) }
                )
            }
        }
    }
}

private enum SkillManagementPrompt: String, Identifiable {
    case archive
    case delete

    var id: String { rawValue }
}

private struct InspectorField: View {
    @Environment(\.locale) private var locale
    let title: String
    let value: String
    let mono: Bool
    let copy: (() -> Void)?
    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.8).foregroundStyle(Palette.muted)
            HStack(alignment: .top, spacing: 5) {
                Text(value).font(.system(size: 11, weight: .regular, design: mono ? .monospaced : .default)).foregroundStyle(Palette.secondary).lineLimit(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if let copy {
                    Button(action: copy) { Image(systemName: "doc.on.doc").font(.system(size: 12)) }.buttonStyle(IconButtonStyle()).help(L10n.text("复制或显示", "Copy or reveal"))
                }
            }
        }
    }
}

private struct TransferOption: View {
    @Environment(\.locale) private var locale
    let symbol: String
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        let _ = locale
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(selected ? Palette.mint : Palette.muted).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Palette.mint) }
            }
            .padding(8).background(selected ? Palette.mint.opacity(0.06) : Palette.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Palette.mint.opacity(0.22) : Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct NoticeToast: View {
    let notice: Notice
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Text(notice.message).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 22, y: 8)
    }
    private var icon: String {
        switch notice.style { case .success: "checkmark.circle.fill"; case .warning: "exclamationmark.circle.fill"; case .error: "xmark.circle.fill" }
    }
    private var color: Color {
        switch notice.style { case .success: Palette.mint; case .warning: Palette.amber; case .error: Palette.danger }
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("扫描位置", "Scan Locations")).font(.system(size: 21, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(L10n.text("自动检测已知 Agent 应用与技能目录", "Automatically detect supported Agent apps and skill folders")).font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(IconButtonStyle())
            }
            Divider().overlay(Palette.line)
            SettingsPath(label: "SkillDock Library", path: store.libraryDirectory.path)
            SettingsPath(label: L10n.text("全局 · ~/.agent", "Global · ~/.agent"), path: "\(store.dotAgentPath.path) · \(store.dotAgentStatus)")
            SettingsPath(label: L10n.text("共享 · Codex / DeepSeek / Mirasim", "Shared · Codex / DeepSeek / Mirasim"), path: store.sharedDirectory.path)
            SettingsPath(label: L10n.text("全局归档", "Archived global"), path: store.archivedDirectory.path)
            ForEach(AgentKind.allCases) { kind in SettingsPath(label: kind.title, path: kind.skillDirectory.path) }
            Text(L10n.text("拖到共享全局会复制技能到 ~/.agents/skills，供 Codex、DeepSeek Harness 和 Mirasim 使用。Library 用于集中收纳和选择性分配。Mirasim 的本地技能目录为 ~/.mirasim/skills；Codex 使用 ~/.codex/skills；DeepSeek 默认使用 ~/.dsh/skills。Claude Desktop 的本地技能及 synced 子目录作为本机来源展示。", "Drag to Shared global to copy skills into ~/.agents/skills for Codex, DeepSeek Harness, and Mirasim. Library collects skills for selective assignment. Mirasim uses ~/.mirasim/skills; Codex uses ~/.codex/skills; DeepSeek defaults to ~/.dsh/skills. Claude Desktop’s local skills and synced subfolder are shown as local sources."))
                .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(L10n.text("当前电脑上的应用自动检测中。远端电脑需要额外的同步连接。", "Apps on this Mac are detected automatically. Remote computers require a separate sync connection."))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer()
                Button(L10n.text("重新扫描", "Rescan")) { store.refresh(); dismiss() }.buttonStyle(AccentButtonStyle())
            }
        }
        .padding(20).frame(width: 580).background(Palette.panel)
    }
}

private struct SettingsPath: View {
    let label: String
    let path: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary).frame(width: 150, alignment: .leading)
            Text(path).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }
}

private struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.mintInk.opacity(isEnabled ? 1 : 0.48)).padding(.horizontal, 11).frame(height: 36)
            .background(Palette.mint.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.2), in: RoundedRectangle(cornerRadius: 7)).scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary.opacity(isEnabled ? 1 : 0.5)).padding(.horizontal, 10).frame(height: 36)
            .background(isEnabled && configuration.isPressed ? Palette.hover : Palette.raised.opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.lineStrong.opacity(isEnabled ? 1 : 0.55), lineWidth: 1)).scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.danger.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Palette.danger.opacity(isEnabled ? (configuration.isPressed ? 0.14 : 0.08) : 0.04), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.danger.opacity(isEnabled ? 0.34 : 0.14), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(configuration.isPressed ? Palette.mint : Palette.secondary).padding(.horizontal, 9).frame(height: 34)
            .background(configuration.isPressed ? Palette.hover : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(configuration.isPressed ? Palette.mint : Palette.muted).frame(width: 30, height: 30)
            .background(configuration.isPressed ? Palette.hover : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }
}
