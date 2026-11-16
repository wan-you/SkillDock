#!/bin/zsh
# SkillDock from the command line: list, share, globalize, archive and find duplicate Agent skills.
set -euo pipefail

typeset -A DIRS
DIRS=(
  global   "$HOME/.agents/skills"
  library  "$HOME/Library/Application Support/SkillDock/Library"
  archived "$HOME/.agents/archived-skills"
  codex    "$HOME/.codex/skills"
  claude   "$HOME/.claude/skills"
  dsh      "${DSH_HOME:-$HOME/.dsh}/skills"
  mirasim  "$HOME/.mirasim/skills"
  grok     "${GROK_HOME:-$HOME/.grok}/skills"
)
ORDER=(global library codex claude dsh mirasim grok archived)

die() { print -u2 "skilldock: $*"; exit 1; }
dir_of() { [[ -n "${DIRS[$1]:-}" ]] || die "unknown location '$1' (use: ${ORDER[*]})"; print -r -- "${DIRS[$1]}"; }

# Skill folders directly inside a location (folders or links containing SKILL.md).
skills_in() {
  local d="$1"; [[ -d "$d" ]] || return 0
  local s; for s in "$d"/*(N); do [[ -f "$s/SKILL.md" ]] && print -r -- "$s"; done
}

# First location holding a skill with this folder name, in SkillDock's source order.
find_skill() {
  local name="$1" loc; for loc in "${ORDER[@]}"; do
    [[ -f "${DIRS[$loc]}/$name/SKILL.md" ]] && { print -r -- "${DIRS[$loc]}/$name"; return; }
  done
  die "no skill named '$name'"
}

describe() {
  local s="$1" kind="copy"
  [[ -L "$s" ]] && kind="link -> $(readlink "$s")"
  local desc=$(awk '/^description:/{sub(/^description:[ ]*/,""); print; exit}' "$s/SKILL.md" | cut -c1-90)
  printf '  %-32s %s\n' "${s:t}" "[$kind] $desc"
}

cmd_list() {
  local locs=("${@:-${ORDER[@]}}") loc s
  for loc in "${locs[@]}"; do
    local d=$(dir_of "$loc"); local items=("${(@f)$(skills_in "$d")}")
    items=(${items:#})
    print "$loc  ($d) · ${#items} skills"
    for s in "${items[@]}"; do describe "$s"; done
  done
}

# Fingerprint of a skill folder's files, ignoring Finder metadata.
fingerprint() {
  (cd "$1" && find . -type f ! -name .DS_Store -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
}

cmd_dupes() {
  typeset -A seen; local loc s fp found=0
  for loc in "${ORDER[@]}"; do
    [[ "$loc" == archived ]] && continue
    for s in ${(f)"$(skills_in "${DIRS[$loc]}")"}; do
      [[ -L "$s" ]] && continue
      fp=$(fingerprint "$s")
      if [[ -n "${seen[$fp]:-}" ]]; then
        print "identical: ${seen[$fp]}  ==  $s"; found=1
      else
        seen[$fp]="$s"
      fi
    done
  done
  (( found )) || print "No identical skill copies found."
}

cmd_share() {
  local name="$1" target="$2" mode="${3:-link}"
  local src=$(find_skill "$name") dest="$(dir_of "$target")/$name"
  [[ -e "$dest" || -L "$dest" ]] && die "$dest already exists; leaving it unchanged"
  mkdir -p "${dest:h}"
  if [[ "$mode" == --copy ]]; then cp -R "$src" "$dest"; print "Copied $src -> $dest"
  else ln -s "${src:A}" "$dest"; print "Linked $dest -> ${src:A}"; fi
}

cmd_archive() {
  local name="$1" src dest="${DIRS[archived]}/$1"
  if [[ -n "${2:-}" ]]; then src="$(dir_of "$2")/$name"; [[ -f "$src/SKILL.md" ]] || die "no skill named '$name' in $2"
  else src=$(find_skill "$name"); fi
  [[ "$src" == "${DIRS[archived]}"/* ]] && die "$name is already archived"
  [[ -e "$dest" ]] && die "$dest already exists; leaving it unchanged"
  mkdir -p "${DIRS[archived]}"; mv "$src" "$dest"; print "Archived $src -> $dest"
}

cmd_app() {
  local repo="${SKILLDOCK_REPO:-$HOME/SkillDock}" app="${1:-$HOME/Applications/SkillDock.app}"
  [[ -d "$repo/.git" ]] || git clone --depth 1 https://github.com/wany26/SkillDock.git "$repo"
  "$repo/scripts/build-macos-app.sh" "$app" && open "$app"
}

case "${1:-help}" in
  list)    shift; cmd_list "$@" ;;
  dupes)   cmd_dupes ;;
  share)   (( $# >= 3 )) || die "usage: share <skill> <location> [--copy]"; cmd_share "$2" "$3" "${4:-link}" ;;
  global)  (( $# == 2 )) || die "usage: global <skill>"; cmd_share "$2" global --copy ;;
  archive) (( $# >= 2 )) || die "usage: archive <skill> [location]"; cmd_archive "$2" "${3:-}" ;;
  where)   (( $# == 2 )) || die "usage: where <skill>"; find_skill "$2" ;;
  app)     shift; cmd_app "$@" ;;
  *) print "usage: skilldock.sh list [location...] | where <skill> | dupes | share <skill> <location> [--copy] | global <skill> | archive <skill> [location] | app [path]
locations: ${ORDER[*]}" ;;
esac
