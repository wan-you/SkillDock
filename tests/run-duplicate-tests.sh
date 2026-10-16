#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skilldock-duplicates.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

# The test executable creates all skills and backups beneath its temporary root.
swiftc -parse-as-library -swift-version 5 \
  "$PROJECT_ROOT/native/SkillFileSafety.swift" \
  "$PROJECT_ROOT/native/SkillDuplicateService.swift" \
  "$PROJECT_ROOT/tests/DuplicateTests.swift" \
  -o "$TEST_ROOT/duplicate-tests"
"$TEST_ROOT/duplicate-tests" "$TEST_ROOT/fixtures"
