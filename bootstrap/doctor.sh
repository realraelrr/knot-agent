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

check_file_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [ ! -f "$path" ]; then
    fail "$label missing: $path"
    return
  fi

  if grep -Fq -- "$pattern" "$path"; then
    ok "$label contains: $pattern"
  else
    fail "$label missing required text: $pattern"
  fi
}

check_file_exists() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    ok "$label: $path"
    return 0
  fi

  fail "$label missing: $path"
  return 1
}

check_file_not_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [ ! -f "$path" ]; then
    fail "$label missing: $path"
    return
  fi

  if grep -Fq -- "$pattern" "$path"; then
    fail "$label contains stale text: $pattern"
  else
    ok "$label does not contain stale text: $pattern"
  fi
}

check_backup_remote() {
  if [ ! -d "$ROOT/.git" ]; then
    fail "backup git repository missing: $ROOT/.git"
    return
  fi

  local backup_url
  backup_url="$(git -C "$ROOT" remote get-url backup 2>/dev/null)" || {
    fail "backup remote missing; configure customer-controlled remote named backup"
    return
  }

  if printf '%s\n' "$backup_url" | grep -qi 'realraelrr/knot-agent'; then
    fail "backup remote points to scaffold repository: $backup_url"
  else
    ok "backup remote: $backup_url"
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

check_cc_connect_build() {
  if [ -x "$ROOT/components/cc-connect-local-main/cc-connect" ]; then
    ok "cc-connect build: $ROOT/components/cc-connect-local-main/cc-connect"
  elif [ -x "$ROOT/components/cc-connect-local-main/dist/cc-connect" ]; then
    ok "cc-connect build: $ROOT/components/cc-connect-local-main/dist/cc-connect"
  else
    fail "cc-connect build missing; run make build-noweb in components/cc-connect-local-main"
  fi
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
check_cc_connect_build
check_dir "$ROOT/components/planning-with-files/.codex/skills/planning-with-files" "planning-with-files source"
check_dir "$ROOT/components/guizang-ppt-skill" "guizang-ppt-skill source"

printf '\nWorkspace\n'
WORKSPACE="$ROOT/workspace"

check_file_contains "$ROOT/.gitignore" "workspace/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "runtime/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "components/" ".gitignore"

check_file_contains "$ROOT/AGENTS.md" "## Permissions" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Session Isolation" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Execution Discipline" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Small tasks" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Medium tasks" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Large tasks" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "planning-with-files" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "human confirmation" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "execute, review" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "deliver with verification" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "independent subagent" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "knot-workflow" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "operator" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "admin" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "member" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Do not check permissions for every harmless IM request" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "modify system files" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "modify durable knowledge" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "edit the permissions table" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "access another user's" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "send files outside the user's own session" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "shared knowledge does not require a permissions check" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Only \`operator\` and \`admin\` may edit" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/sessions/<platform>/<chat_id>/<user_id>/deliverables" "AGENTS.md"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Do not check permissions for every harmless IM request" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "If a permission check is required and the user has no matching row" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "follow \`AGENTS.md\` execution discipline" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Medium or large task" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/sessions/<platform>/<chat_id>/<user_id>/deliverables" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ROOT=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "CC_CONNECT_BIN=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "components/cc-connect-local-main/cc-connect" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "\$KNOT_ROOT/workspace/deliverables/example" "runtime config"

check_dir "$WORKSPACE/inbox" "inbox"
check_dir "$WORKSPACE/knowledge/raw" "knowledge/raw"
check_dir "$WORKSPACE/knowledge/processed" "knowledge/processed"
check_dir "$WORKSPACE/knowledge/vault" "knowledge/vault"
check_dir "$WORKSPACE/work" "work"
check_dir "$WORKSPACE/deliverables" "deliverables"
check_dir "$WORKSPACE/admin" "admin"
check_dir "$WORKSPACE/sessions" "sessions"
if check_file_exists "$WORKSPACE/admin/permissions.md" "permissions"; then
  check_file_contains "$WORKSPACE/admin/permissions.md" "| Platform | Chat ID | User ID | Session Key | Name | Role | Scope | Notes |" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "agent operating contract, not a security sandbox" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`operator\`" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`admin\`" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`member\`" "permissions"
fi
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "| Platform | Chat ID | User ID | Session Key | Name | Role | Scope | Notes |" "permissions template"
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "Only \`operator\` and \`admin\` may edit this file" "permissions template"
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`Scope\` is a human-readable boundary" "permissions template"
if check_file_exists "$WORKSPACE/admin/knowledge-feedback.md" "knowledge feedback"; then
  check_file_contains "$WORKSPACE/admin/knowledge-feedback.md" "| Time | Platform | Chat ID | User ID | Session Key | Name | Topic | Feedback | Evidence | Status | Admin Notes |" "knowledge feedback"
fi
check_file_contains "$ROOT/.skills/knot-setup/references/knowledge-feedback.template.md" "| Time | Platform | Chat ID | User ID | Session Key | Name | Topic | Feedback | Evidence | Status | Admin Notes |" "knowledge feedback template"
if check_file_exists "$WORKSPACE/admin/backup-policy.md" "backup policy"; then
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "committed and pushed by a Codex app" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "customer-controlled git remote" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "remote \`backup\`" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "realraelrr/knot-agent" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "git add -f" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "Never use broad \`git add -A\`" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "runtime/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "components/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "local secrets" "backup policy"
  check_file_not_contains "$WORKSPACE/admin/backup-policy.md" "legacy" "backup policy"
  check_file_not_contains "$WORKSPACE/admin/backup-policy.md" "- knowledge/" "backup policy"
fi
check_file_not_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "legacy" "backup policy template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "- knowledge/" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "controlled \`git add -f\`" "backup automation template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "Do not use broad \`git add -A\`" "backup automation template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "remote \`backup\`" "backup automation template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "realraelrr/knot-agent" "backup automation template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "legacy" "backup automation template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "- knowledge/" "backup automation template"
check_backup_remote
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
