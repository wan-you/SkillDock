---
name: skilldock
description: Manage Agent skills across Codex, Claude, DeepSeek Harness, Mirasim and Grok on macOS, the way the SkillDock app does. List which skills each Agent has, find where a skill lives, share a skill with another Agent by link or copy, make a skill global in ~/.agents/skills, archive it, find identical duplicate copies, or build and open the SkillDock app. Use when the user asks things like "which skills does Codex have", "give Claude the X skill", "make this skill global", "find duplicate skills", "clean up my skills", "archive this skill", "open SkillDock", or mentions SkillDock, even without the word "skill".
---

# SkillDock

SkillDock keeps one view of every Agent skill folder on a Mac. A skill is any folder containing `SKILL.md`. This skill does SkillDock's file operations from the command line through `scripts/skilldock.sh`, and can build the native app when the user wants the GUI.

## Locations

| Name | Folder | Role |
| --- | --- | --- |
| `global` | `~/.agents/skills` | Shared by Codex, DeepSeek Harness, Mirasim and Grok |
| `library` | `~/Library/Application Support/SkillDock/Library` | Collection for selective assignment |
| `codex` | `~/.codex/skills` | Codex |
| `claude` | `~/.claude/skills` | Claude Code and Claude Desktop |
| `dsh` | `$DSH_HOME/skills` or `~/.dsh/skills` | DeepSeek Harness |
| `mirasim` | `~/.mirasim/skills` | Mirasim |
| `grok` | `$GROK_HOME/skills` or `~/.grok/skills` | Grok CLI |
| `archived` | `~/.agents/archived-skills` | Archived skills, ignored by Agents |

When a name exists in several places, the source order is the table order above (global first).

## Commands

Run from this skill's folder:

```sh
scripts/skilldock.sh list [location...]          # skills per location, marked [copy] or [link -> target]
scripts/skilldock.sh where <skill>               # path of the first matching skill
scripts/skilldock.sh dupes                       # identical skill copies (Finder .DS_Store ignored)
scripts/skilldock.sh share <skill> <location>    # symlink the skill into another Agent
scripts/skilldock.sh share <skill> <location> --copy   # independent copy instead
scripts/skilldock.sh global <skill>              # copy into ~/.agents/skills, original kept
scripts/skilldock.sh archive <skill> [location]  # move to ~/.agents/archived-skills
scripts/skilldock.sh app [path]                  # clone, build and open SkillDock.app (default ~/Applications)
```

## How to work

- Start with `list` or `where` so you and the user see the current state before changing anything.
- Prefer `share` (a link) when the user wants one skill kept in sync across Agents; use `--copy` when they want to edit one Agent's version independently.
- The script never overwrites: if the destination name exists it stops and says so. Tell the user and ask before removing or renaming anything yourself.
- `archive` moves a folder, so links pointing at it stop working. Name the location when the skill exists in more than one place, and confirm with the user before archiving.
- `dupes` only reports. To merge duplicates, replace a copy with a link only after the user agrees (`rm -rf` the copy, then `share` from the kept original), or point them to **Organize** in the app, which keeps a restorable backup.
- Claude Desktop's synced and built-in plugin skills are managed by Claude; do not edit or archive them.
- `app` needs Apple Silicon, macOS 14+ and Xcode Command Line Tools. Set `SKILLDOCK_REPO` to use an existing checkout.
