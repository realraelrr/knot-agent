#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORMS=""
FAILURES=0

ok() { printf 'OK   %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; }
fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

usage() {
  cat <<'EOF'
Usage: bash bootstrap/doctor.sh [--platform NAME[,NAME...]]

Platform names: dingtalk, feishu, wecom, weixin
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform)
      shift
      if [ "$#" -eq 0 ]; then
        fail "--platform requires a value"
        break
      fi
      PLATFORMS="${PLATFORMS}${PLATFORMS:+,}$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1: $(command -v "$1")"
  else
    fail "$1 command not found"
  fi
}

check_dir() {
  if [ -d "$1" ]; then
    ok "$2: $1"
  else
    fail "$2 missing: $1"
  fi
}

check_any_dir() {
  local label="$1"
  shift

  for path in "$@"; do
    if [ -d "$path" ]; then
      ok "$label: $path"
      return
    fi
  done

  fail "$label missing"
}

check_macos_app() {
  local name="$1"

  if command -v mdfind >/dev/null 2>&1; then
    local found
    found="$(mdfind "kMDItemFSName == '${name}.app'" | head -1)"
    if [ -n "$found" ]; then
      ok "${name}.app: $found"
      return
    fi
  fi

  warn "${name}.app not found by Spotlight"
}

check_skill_file() {
  local path="$1"
  local label="$2"

  if [ -f "$path/SKILL.md" ]; then
    ok "$label: $path"
    return 0
  else
    fail "$label missing SKILL.md: $path"
    return 1
  fi
}

resolve_symlink() {
  local path="$1"
  local target

  target="$(readlink "$path")" || return 1
  case "$target" in
    /*)
      printf '%s\n' "$target"
      ;;
    *)
      (cd "$(dirname "$path")/$target" 2>/dev/null && pwd)
      ;;
  esac
}

check_skill_link() {
  local name="$1"
  local expected="$2"
  local dest="$HOME/.codex/skills/$name"
  local resolved

  check_skill_file "$dest" "$name skill" || return

  if [ ! -L "$dest" ]; then
    fail "$name skill is not a symlink: $dest"
    return
  fi

  resolved="$(resolve_symlink "$dest")" || {
    fail "$name skill symlink cannot be resolved: $dest"
    return
  }

  if [ "$resolved" = "$expected" ]; then
    ok "$name skill target: $resolved"
  else
    fail "$name skill points to $resolved, expected $expected"
  fi
}

check_platform() {
  local platform="$1"

  case "$platform" in
    dingtalk|feishu|wecom)
      check_dir "$ROOT/runtime/dingtalk-feishu-wecom" "$platform runtime"
      check_dir "$ROOT/runtime/dingtalk-feishu-wecom/bin" "$platform runtime bin"
      if [ -x "$ROOT/runtime/dingtalk-feishu-wecom/bin/cc-connect" ]; then
        ok "$platform cc-connect binary"
      else
        fail "$platform cc-connect binary missing or not executable"
      fi
      if [ -f "$ROOT/runtime/dingtalk-feishu-wecom/config.$platform.toml" ]; then
        ok "$platform config"
      else
        fail "$platform config missing"
      fi
      if [ -x "$ROOT/runtime/dingtalk-feishu-wecom/run-$platform.sh" ]; then
        ok "$platform run script"
      else
        fail "$platform run script missing or not executable"
      fi
      ;;
    weixin)
      check_dir "$ROOT/runtime/weixin" "weixin runtime"
      check_dir "$ROOT/runtime/weixin/bin" "weixin runtime bin"
      if [ -x "$ROOT/runtime/weixin/bin/cc-connect" ]; then
        ok "weixin cc-connect binary"
      else
        fail "weixin cc-connect binary missing or not executable"
      fi
      if [ -f "$ROOT/runtime/weixin/config.weixin.toml" ]; then
        ok "weixin config"
      else
        fail "weixin config missing"
      fi
      if [ -x "$ROOT/runtime/weixin/run-weixin.sh" ]; then
        ok "weixin run script"
      else
        fail "weixin run script missing or not executable"
      fi
      ;;
    "")
      ;;
    *)
      fail "unknown platform: $platform"
      ;;
  esac
}

printf 'Knot doctor\n'
printf 'Root: %s\n\n' "$ROOT"

check_cmd codex
check_macos_app Codex
check_macos_app Obsidian

printf '\nSkills\n'
check_skill_link "planning-with-files" "$ROOT/components/planning-with-files/.codex/skills/planning-with-files"
check_skill_link "docling-skill" "$ROOT/components/docling-skill"
check_skill_link "guizang-ppt-skill" "$ROOT/components/guizang-ppt-skill"
check_skill_link "knot-setup" "$ROOT/.skills/knot-setup"
check_skill_link "knot-workflow" "$ROOT/.skills/knot-workflow"
check_skill_link "wiki-ingest" "$ROOT/components/obsidian-wiki/.skills/wiki-ingest"
check_skill_link "wiki-query" "$ROOT/components/obsidian-wiki/.skills/wiki-query"
check_skill_link "wiki-status" "$ROOT/components/obsidian-wiki/.skills/wiki-status"

printf '\nComponents\n'
check_dir "$ROOT/components/docling-skill" "docling-skill source"
check_dir "$ROOT/components/obsidian-wiki" "obsidian-wiki"
check_dir "$ROOT/components/cc-connect-local-main" "cc-connect source"
check_dir "$ROOT/components/planning-with-files/.codex/skills/planning-with-files" "planning-with-files source"
check_dir "$ROOT/components/guizang-ppt-skill" "guizang-ppt-skill source"

printf '\nWorkspace\n'
WORKSPACE="$ROOT/workspace"

check_dir "$WORKSPACE/inbox" "inbox"
check_dir "$WORKSPACE/knowledge/raw" "knowledge/raw"
check_dir "$WORKSPACE/knowledge/processed" "knowledge/processed"
check_dir "$WORKSPACE/knowledge/vault" "knowledge/vault"
check_dir "$WORKSPACE/work" "work"
check_dir "$WORKSPACE/deliverables" "deliverables"
check_dir "$ROOT/runtime" "runtime"
check_dir "$WORKSPACE/.state/tasks" ".state/tasks"

if [ -n "$PLATFORMS" ]; then
  printf '\nPlatforms\n'
  warn "platform checks validate files only; credentials and /whoami authorization require live IM verification"
  OLD_IFS="$IFS"
  IFS=","
  for platform in $PLATFORMS; do
    check_platform "$platform"
  done
  IFS="$OLD_IFS"
else
  printf '\nPlatforms\n'
  warn "no platform checks requested; use --platform dingtalk,feishu,wecom,weixin"
fi

printf '\nDone.\n'

if [ "$FAILURES" -gt 0 ]; then
  printf 'FAILED %s required check(s).\n' "$FAILURES"
  exit 1
fi
