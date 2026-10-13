#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skilldock-security.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
export SKILLDOCK_TEST_HOME="$TEST_ROOT/home"
# Ignore an existing DeepSeek override while testing isolated skill locations.
unset DSH_HOME

python3 - "$PROJECT_ROOT" "$TEST_ROOT" <<'PY'
from pathlib import Path
import re
import sys

project, output = map(Path, sys.argv[1:])
app = (project / "native/SkillDockApp.swift").read_text()
app = app.split("@main\n", 1)[0]
# Keep Store, scanning, policies, and filesystem operations unchanged. Supply
# only a test home and a deterministic empty installed-application inventory.
start = app.index("    private func discoverAgents() -> [InstalledAgent] {")
end = app.index("    private func scanSkills() -> [SkillItem] {", start)
app = app[:start] + "    private func discoverAgents() -> [InstalledAgent] { [] }\n\n" + app[end:]

def isolated_home(source):
    return re.sub(r"(?:FileManager\.default|fm|fileManager)\.homeDirectoryForCurrentUser",
                  "securityTestHome", source)

app = isolated_home(app)
opening = isolated_home((project / "native/SkillOpenService.swift").read_text())
assert "homeDirectoryForCurrentUser" not in app + opening
(output / "SecurityTests.swift").write_text(app + "\n" + (project / "tests/SecurityTests.swift").read_text())
(output / "SkillOpenService.swift").write_text(opening)
PY

swiftc -parse-as-library -swift-version 5 \
  "$PROJECT_ROOT/native/SkillFileSafety.swift" \
  "$PROJECT_ROOT/tests/FileSafetyTests.swift" \
  -o "$TEST_ROOT/file-safety-tests"
"$TEST_ROOT/file-safety-tests"

swiftc -parse-as-library -swift-version 5 -framework SwiftUI -framework AppKit \
  "$TEST_ROOT/SecurityTests.swift" \
  "$TEST_ROOT/SkillOpenService.swift" \
  "$PROJECT_ROOT/native/SkillFileSafety.swift" \
  -o "$TEST_ROOT/security-tests"
"$TEST_ROOT/security-tests"
