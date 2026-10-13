# SkillDock

[简体中文](README.zh-CN.md)

SkillDock is a native macOS app for managing Agent skills. Discover Codex, Claude Desktop, and DeepSeek Harness, collect skills in one Library, and drag them onto the Agents that need them.

![SkillDock](docs/images/skilldock.png)

## Features

- **Drag to share.** Link Agents to the same skill files or create independent copies.
- **See connections.** Hover the relationship button on a skill card to see its sources and downstream Agents, connected by arrows.
- **Find and organize.** Search names, descriptions, aliases, and paths; sort by name, source, or recent modification. Built-in skills start collapsed.
- **Manage skills.** Collect skills in the Library, archive them, or delete them from the detail panel.
- **Open your tools.** Open a skill folder in Terminal, VS Code, Codex, or Claude Desktop from its card or detail panel.
- **Choose your view.** Switch between light, dark, and system appearance, and between English and Simplified Chinese.

## Build and launch

Requires Apple Silicon, macOS 14 or later, and Xcode 15 or later Command Line Tools:

```sh
xcode-select --install
```

```sh
git clone https://github.com/wany26/SkillDock.git
cd SkillDock
./scripts/build-macos-app.sh
open "$HOME/Desktop/SkillDock.app"
```

To build elsewhere, pass the destination app path:

```sh
./scripts/build-macos-app.sh /Applications/SkillDock.app
```

## Use

1. Select an Agent in the sidebar to view its skills.
2. Drag a skill onto an Agent or its skill list. Choose **Create a link** to share its files, or **Create a copy** to edit it independently.
3. Drag skills onto **Library** to collect them for selective assignment. Drag an eligible skill onto **Archived** to archive it.
4. Select a skill for its details and management actions. Use **Open**, or right-click its card, to choose an application.

Press **⌘F** to search and **Esc** to clear the query. Use the list sorting menu and the top-bar **Appearance** and **Language** menus to change the view. Sorting, appearance, and language choices are saved.

## Skill locations

Skills are discovered from folders containing `SKILL.md`.

| Location | Role |
| --- | --- |
| `~/Library/Application Support/SkillDock/Library` | Collection for selective assignment to Agents |
| `~/.agents/skills` | Shared skills loaded by Codex and DeepSeek Harness |
| `~/.agent` and `~/.agent/skills` | Additional global sources |
| `~/.agents/archived-skills` | Archived skills |
| `~/.codex/skills` | Codex skills |
| `~/.claude/skills` | Claude Desktop local skills, including its `synced` subfolder |
| `~/.dsh/skills` | DeepSeek Harness skills; uses `$DSH_HOME/skills` when configured |

## Development

| File | Purpose |
| --- | --- |
| `native/SkillDockApp.swift` | SwiftUI interface, discovery, and skill management |
| `native/SkillOpenService.swift` | Native application opening |
| `scripts/build-macos-app.sh` | App bundle build and signing |
| `scripts/generate-app-icon.swift` | App icon generation |

Regenerate the icon assets:

```sh
swift scripts/generate-app-icon.swift native/Resources
```

## License

[MIT](LICENSE)
