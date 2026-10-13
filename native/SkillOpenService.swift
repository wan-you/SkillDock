import AppKit
import Foundation

enum SkillOpenTarget: String, CaseIterable, Identifiable {
    case terminal
    case visualStudioCode
    case codex
    case claudeDesktop

    var id: String { rawValue }

    var applicationName: String {
        switch self {
        case .terminal: "Terminal"
        case .visualStudioCode: "VS Code"
        case .codex: "Codex"
        case .claudeDesktop: "Claude Desktop"
        }
    }

    var symbol: String {
        switch self {
        case .terminal: "terminal"
        case .visualStudioCode: "curlybraces"
        case .codex: "hexagon"
        case .claudeDesktop: "sparkle"
        }
    }

    var chineseTitle: String {
        switch self {
        case .terminal: "在终端中打开"
        case .visualStudioCode: "在 VS Code 中打开"
        case .codex: "在 Codex 中打开"
        case .claudeDesktop: "在 Claude Desktop 中打开"
        }
    }

    var englishTitle: String { "Open in \(applicationName)" }

    var bundleIdentifiers: [String] {
        switch self {
        case .terminal: ["com.apple.Terminal"]
        case .visualStudioCode: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .codex: ["com.openai.codex", "com.openai.chat"]
        case .claudeDesktop: ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        }
    }
}

struct SkillOpenRequest {
    let target: SkillOpenTarget
    let applicationURL: URL
    let directory: URL
    let urls: [URL]
}

struct SkillOpenOutcome {
    let target: SkillOpenTarget
    let directory: URL

    var chineseMessage: String {
        switch target {
        case .terminal: "已在终端中打开技能目录"
        case .visualStudioCode: "已在 VS Code 中打开技能目录和 SKILL.md"
        case .codex: "已在 Codex 中打开技能目录，可开始新聊天"
        case .claudeDesktop: "已在 Claude Desktop 中打开技能目录，可开始新聊天"
        }
    }

    var englishMessage: String {
        switch target {
        case .terminal: "Opened the skill folder in Terminal"
        case .visualStudioCode: "Opened the skill folder and SKILL.md in VS Code"
        case .codex: "Opened the skill folder in Codex, ready for a new chat"
        case .claudeDesktop: "Opened the skill folder in Claude Desktop, ready for a new chat"
        }
    }
}

enum SkillOpenError: Error {
    case applicationUnavailable(SkillOpenTarget)
    case unsupportedFolderOpening(SkillOpenTarget)
    case missingDirectory
    case missingDefinition
    case launchFailed(SkillOpenTarget, String)

    var chineseMessage: String {
        switch self {
        case .applicationUnavailable(let target): "未找到 \(target.applicationName)，请先安装该应用"
        case .unsupportedFolderOpening(let target): "当前版本的 \(target.applicationName) 不支持打开本地目录，请更新该应用"
        case .missingDirectory: "技能目录不存在或无法访问，请刷新后重试"
        case .missingDefinition: "未找到 SKILL.md，请刷新后重试"
        case .launchFailed(let target, let detail): "无法在 \(target.applicationName) 中打开：\(detail)"
        }
    }

    var englishMessage: String {
        switch self {
        case .applicationUnavailable(let target): "\(target.applicationName) was not found. Install the app first."
        case .unsupportedFolderOpening(let target): "This version of \(target.applicationName) cannot open local folders. Update the app first."
        case .missingDirectory: "The skill folder is missing or inaccessible. Refresh and try again."
        case .missingDefinition: "SKILL.md was not found. Refresh and try again."
        case .launchFailed(let target, let detail): "Could not open in \(target.applicationName): \(detail)"
        }
    }
}

@MainActor
enum SkillOpenService {
    static func applicationURL(for target: SkillOpenTarget) -> URL? {
        let workspace = NSWorkspace.shared
        for identifier in target.bundleIdentifiers {
            if let url = workspace.urlForApplication(withBundleIdentifier: identifier),
               isApplication(url, for: target) {
                return url
            }
        }

        // A bundle can exist before Launch Services has indexed it.
        let fileManager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
                     URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true)]
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for url in children where url.pathExtension.lowercased() == "app" {
                if isApplication(url, for: target) { return url }
            }
        }
        return nil
    }

    static func supportsFolderOpening(applicationURL: URL) -> Bool {
        guard let types = Bundle(url: applicationURL)?.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] else {
            return false
        }
        return types.contains { type in
            let contentTypes = type["LSItemContentTypes"] as? [String] ?? []
            return contentTypes.contains("public.folder") || contentTypes.contains("public.directory")
        }
    }

    // This pure request builder can be tested without launching an application.
    static func prepare(target: SkillOpenTarget, directory: URL, applicationURL: URL? = nil) throws -> SkillOpenRequest {
        guard directory.isFileURL else { throw SkillOpenError.missingDirectory }
        let folder = directory.standardizedFileURL.resolvingSymlinksInPath()
        let fileManager = FileManager.default
        guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              fileManager.isReadableFile(atPath: folder.path),
              fileManager.isExecutableFile(atPath: folder.path) else {
            throw SkillOpenError.missingDirectory
        }
        guard let application = applicationURL ?? self.applicationURL(for: target),
              isApplication(application, for: target) else {
            throw SkillOpenError.applicationUnavailable(target)
        }
        guard supportsFolderOpening(applicationURL: application) else {
            throw SkillOpenError.unsupportedFolderOpening(target)
        }

        var urls = [folder]
        if target == .visualStudioCode {
            let definition = folder.appendingPathComponent("SKILL.md", isDirectory: false)
            guard (try? definition.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  fileManager.isReadableFile(atPath: definition.path) else {
                throw SkillOpenError.missingDefinition
            }
            urls.append(definition)
        }
        // Native document-open events preserve every path character as data.
        // Terminal handles directories itself; no command or AppleScript is sent.
        // Codex selects a project. Claude chooses its Code or Cowork folder flow.
        // Neither Agent receives a prompt or a send action.
        return SkillOpenRequest(target: target, applicationURL: application,
                                directory: folder, urls: urls)
    }

    static func open(target: SkillOpenTarget, directory: URL) async throws -> SkillOpenOutcome {
        let request = try prepare(target: target, directory: directory)
        return try await open(request)
    }

    static func open(_ request: SkillOpenRequest) async throws -> SkillOpenOutcome {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(request.urls, withApplicationAt: request.applicationURL,
                                    configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: SkillOpenError.launchFailed(request.target, error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
        return SkillOpenOutcome(target: request.target, directory: request.directory)
    }

    private static func isApplication(_ url: URL, for target: SkillOpenTarget) -> Bool {
        guard url.isFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              target.bundleIdentifiers.contains(identifier) else { return false }
        if target == .codex && identifier == "com.openai.chat" {
            // The classic ChatGPT bundle shares this identifier but cannot open
            // Codex projects. The current combined desktop app registers codex:.
            let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
            return urlTypes.contains { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains("codex") }
        }
        return true
    }
}
