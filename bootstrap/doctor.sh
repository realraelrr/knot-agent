#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DIR="$CODEX_HOME_DIR/skills"
PLATFORMS=""
SCAFFOLD_ONLY=0
FAILURES=0

ok() { printf 'OK   %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; }
fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

usage() {
  cat <<'EOF'
Usage: bash bootstrap/doctor.sh [--scaffold-only] [--platform NAME[,NAME...]]

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
    --scaffold-only)
      SCAFFOLD_ONLY=1
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

check_executable() {
  local path="$1"
  local label="$2"

  if [ -x "$path" ]; then
    ok "$label: $path"
  else
    fail "$label missing or not executable: $path"
  fi
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

  local unsafe_remote
  local unsafe_url
  for unsafe_remote in origin scaffold; do
    unsafe_url="$(git -C "$ROOT" remote get-url "$unsafe_remote" 2>/dev/null || true)"
    if [ -n "$unsafe_url" ] && [ "$backup_url" = "$unsafe_url" ]; then
      fail "backup remote matches $unsafe_remote; configure a customer-controlled backup remote"
    fi
  done
}

run_helper_smoke_tests() {
  if ! bash "$ROOT/tests/integration.sh" --root "$ROOT"; then
    fail "integration smoke tests failed"
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

check_skill_link() {
  local name="$1"
  local expected="$2"
  local dest="$SKILLS_DIR/$name"
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
    dingtalk|feishu|wecom|weixin)
      if bash "$ROOT/bootstrap/knot-runtime-check.sh" --root "$ROOT" --platform "$platform"; then
        ok "$platform runtime check passed"
      else
        fail "$platform runtime check failed"
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

installer_ref() {
  local name="$1"
  sed -n "s/^${name}=\"\\([^\"]*\\)\"/\\1/p" "$ROOT/bootstrap/knot-install.sh" | tail -1
}

check_component_ref() {
  local label="$1"
  local dir="$2"
  local ref_name="$3"
  local expected
  local current

  expected="$(installer_ref "$ref_name")"
  if [ -z "$expected" ]; then
    fail "$label pinned revision missing from knot-install.sh: $ref_name"
    return
  fi

  if [ ! -d "$dir/.git" ]; then
    fail "$label git repository missing: $dir"
    return
  fi

  current="$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null)" || {
    fail "$label current revision unavailable: $dir"
    return
  }

  if [ "$current" = "$expected" ]; then
    ok "$label pinned revision: $current"
  else
    fail "$label revision is $current, expected $expected"
  fi
}

run_scaffold_only_checks() {
  printf '\nScaffold source\n'
  check_file_exists "$ROOT/.skills/knot-setup/references/codex-agents.template.md" "Codex global AGENTS template"
  check_file_exists "$ROOT/.skills/knot-setup/references/AGENTS.template.md" "project AGENTS template"
  check_file_exists "$ROOT/.skills/knot-setup/SKILL.md" "knot-setup skill"
  check_file_exists "$ROOT/.skills/knot-workflow/SKILL.md" "knot-workflow skill"
  check_file_exists "$ROOT/bootstrap/lib.sh" "bootstrap shell library"
  check_executable "$ROOT/tests/integration.sh" "integration smoke tests"

  check_executable "$ROOT/bootstrap/knot-workspace.sh" "knot-workspace helper"
  check_executable "$ROOT/bootstrap/knot-install.sh" "knot-install helper"
  check_executable "$ROOT/bootstrap/knot-attachment.sh" "knot-attachment helper"
  check_executable "$ROOT/bootstrap/knot-deliver.sh" "knot-deliver helper"
  check_executable "$ROOT/bootstrap/knot-backup.sh" "knot-backup helper"
  check_executable "$ROOT/bootstrap/knot-runtime-check.sh" "knot-runtime-check helper"

  check_file_contains "$ROOT/.gitignore" ".state/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "workspace/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "runtime/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "components/" ".gitignore"

  check_file_contains "$ROOT/AGENTS.md" "## Layout" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Workflow" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Active Workspaces" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Authorization" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Knowledge" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Delivery" "AGENTS.md"
  check_file_not_contains "$ROOT/AGENTS.md" "## Execution Modes" "AGENTS.md"
  check_file_not_contains "$ROOT/AGENTS.md" "## Backup Automation" "AGENTS.md"
  check_file_not_contains "$ROOT/AGENTS.md" "## Skill Packs" "AGENTS.md"

  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Use the lightest execution weight" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-ingest skill" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available spreadsheet, document" "knot-workflow"
  check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-xlsx" "knot-workflow"
  check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "docling-skill" "knot-workflow"
  check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "wiki-ingest" "knot-workflow"

  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/users/<user_slug>/deliverables" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/groups/<group_slug>/deliverables" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-workspace.sh" "runtime config"
  check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ACTIVE_WORKSPACE=" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "bootstrap/knot-backup.sh" "backup policy template"
  check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "bash bootstrap/knot-backup.sh" "backup automation template"

  printf '\nSmoke tests\n'
  run_helper_smoke_tests
}

printf 'Knot doctor\n'
printf 'Root: %s\n\n' "$ROOT"

if [ "$SCAFFOLD_ONLY" -eq 1 ]; then
  run_scaffold_only_checks
  printf '\nDone.\n'
  if [ "$FAILURES" -gt 0 ]; then
    printf 'FAILED %s required check(s).\n' "$FAILURES"
    exit 1
  fi
  exit 0
fi

check_cmd codex
check_macos_app Codex
check_macos_app Obsidian
check_file_exists "$ROOT/.skills/knot-setup/references/codex-agents.template.md" "Codex global AGENTS template"
check_file_exists "$CODEX_HOME_DIR/AGENTS.md" "Codex global AGENTS.md"
if [ -f "$CODEX_HOME_DIR/AGENTS.override.md" ]; then
  warn "Codex global AGENTS.override.md exists and overrides AGENTS.md: $CODEX_HOME_DIR/AGENTS.override.md"
else
  ok "Codex global AGENTS.override.md absent"
fi

printf '\nSkills\n'
check_skill_link "planning-with-files" "$ROOT/components/planning-with-files/.codex/skills/planning-with-files"
check_skill_link "docling-skill" "$ROOT/components/docling-skill/.codex/skills/docling-skill"
check_skill_link "md-for-human" "$ROOT/components/md-for-human/.codex/skills/md-for-human"
check_skill_link "office-xlsx" "$ROOT/components/knot-skills/skills/office-xlsx"
check_skill_link "office-pptx" "$ROOT/components/knot-skills/skills/office-pptx"
check_skill_link "office-docx" "$ROOT/components/knot-skills/skills/office-docx"
check_skill_link "office-pdf" "$ROOT/components/knot-skills/skills/office-pdf"
check_skill_link "web-ppt" "$ROOT/components/knot-skills/skills/web-ppt"
check_skill_link "handoff" "$ROOT/components/handoff-skill/.codex/skills/handoff"
check_skill_link "knot-setup" "$ROOT/.skills/knot-setup"
check_skill_link "knot-workflow" "$ROOT/.skills/knot-workflow"
check_skill_link "wiki-ingest" "$ROOT/components/obsidian-wiki/.skills/wiki-ingest"
check_skill_link "wiki-query" "$ROOT/components/obsidian-wiki/.skills/wiki-query"
check_skill_link "wiki-status" "$ROOT/components/obsidian-wiki/.skills/wiki-status"

printf '\nComponents\n'
check_dir "$ROOT/components/docling-skill/.codex/skills/docling-skill" "docling-skill source"
check_dir "$ROOT/components/md-for-human/.codex/skills/md-for-human" "md-for-human source"
check_dir "$ROOT/components/handoff-skill/.codex/skills/handoff" "handoff source"
check_dir "$ROOT/components/obsidian-wiki" "obsidian-wiki"
check_dir "$ROOT/components/cc-connect-local-main" "cc-connect source"
check_cc_connect_build
check_dir "$ROOT/components/planning-with-files/.codex/skills/planning-with-files" "planning-with-files source"
check_executable "$ROOT/components/knot-skills/scripts/install-codex-skills.sh" "knot-skills installer"
check_dir "$ROOT/components/knot-skills/skills/office-xlsx" "office-xlsx source"
check_dir "$ROOT/components/knot-skills/skills/office-pptx" "office-pptx source"
check_dir "$ROOT/components/knot-skills/skills/office-docx" "office-docx source"
check_dir "$ROOT/components/knot-skills/skills/office-pdf" "office-pdf source"
check_dir "$ROOT/components/knot-skills/skills/web-ppt" "web-ppt source"
check_file_exists "$ROOT/components/knot-skills/skills/office-docx/scripts/dotnet/OfficeDocx.Cli/OfficeDocx.Cli.csproj" "office-docx CLI project"
check_file_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "active user workspace" "web-ppt skill"
check_file_not_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "workspace/deliverables" "web-ppt skill"
check_file_not_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "current session" "web-ppt skill"
check_component_ref "docling-skill component" "$ROOT/components/docling-skill" "DOCLING_SKILL_REF"
check_component_ref "md-for-human component" "$ROOT/components/md-for-human" "MD_FOR_HUMAN_REF"
check_component_ref "handoff-skill component" "$ROOT/components/handoff-skill" "HANDOFF_SKILL_REF"
check_component_ref "obsidian-wiki component" "$ROOT/components/obsidian-wiki" "OBSIDIAN_WIKI_REF"
check_component_ref "cc-connect component" "$ROOT/components/cc-connect-local-main" "CC_CONNECT_REF"
check_component_ref "planning-with-files component" "$ROOT/components/planning-with-files" "PLANNING_WITH_FILES_REF"
check_component_ref "knot-skills component" "$ROOT/components/knot-skills" "KNOT_SKILLS_REF"

printf '\nWorkspace\n'
WORKSPACE="$ROOT/workspace"

check_file_contains "$ROOT/.gitignore" ".state/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "workspace/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "runtime/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "components/" ".gitignore"

if [ -e "$ROOT/bootstrap/knot-session.sh" ] || [ -L "$ROOT/bootstrap/knot-session.sh" ]; then
  fail "legacy knot-session helper must be removed"
else
  ok "legacy knot-session helper removed"
fi
check_executable "$ROOT/bootstrap/knot-workspace.sh" "knot-workspace helper"
check_executable "$ROOT/bootstrap/knot-install.sh" "knot-install helper"
check_executable "$ROOT/bootstrap/knot-attachment.sh" "knot-attachment helper"
check_executable "$ROOT/bootstrap/knot-deliver.sh" "knot-deliver helper"
check_executable "$ROOT/bootstrap/knot-backup.sh" "knot-backup helper"
check_executable "$ROOT/bootstrap/knot-runtime-check.sh" "knot-runtime-check helper"
check_file_exists "$ROOT/bootstrap/lib.sh" "bootstrap shell library"
check_executable "$ROOT/tests/integration.sh" "integration smoke tests"
check_file_contains "$ROOT/AGENTS.md" "## Layout" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "components/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "runtime/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Workflow" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "knot-workflow" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/.state/tasks/<task_id>/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Active Workspaces" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-workspace.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "KNOT_ACTIVE_WORKSPACE" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "KNOT_GROUP_WORKSPACE" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/conversations/<platform>/<chat_id>/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Authorization" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/admin/permissions.md" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "access another user's workspace" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Knowledge" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/knowledge/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "visible diff" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Delivery" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-attachment.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-deliver.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/users/<user_slug>/deliverables" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "cc-connect-attachments" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "## Execution Modes" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "## Backup Automation" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "## Skill Packs" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "Office Pack" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "Agent Workbench" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "Roles:" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "bootstrap/knot-session.sh" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "workspace/sessions" "AGENTS.md"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Use the lightest execution weight" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "**quick**" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "**durable**" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "**risky**" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/admin/permissions.md" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Default to the user-visible result" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-workspace.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-attachment.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-deliver.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-backup.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-runtime-check.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "KNOT_ACTIVE_WORKSPACE" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/conversations/<platform>/<chat_id>/" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-session.sh" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/sessions" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-ingest skill" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-query skill" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available spreadsheet, document" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-xlsx" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-pptx" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-docx" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-pdf" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "web-ppt" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "md-for-human" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "docling-skill" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "wiki-ingest" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "wiki-query" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/users/<user_slug>/deliverables" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/groups/<group_slug>/deliverables" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ROOT=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "[projects.knot_workspace]" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "Do not set a static agent \`work_dir\`" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ACTIVE_WORKSPACE=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "CC_CONNECT_BIN=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "components/cc-connect-local-main/cc-connect" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-workspace.sh" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-attachment.sh" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-runtime-check.sh" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "\$KNOT_ROOT/workspace/deliverables/example" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-session.sh" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/sessions" "runtime config"

check_dir "$WORKSPACE/knowledge/raw" "knowledge/raw"
check_dir "$WORKSPACE/knowledge/processed" "knowledge/processed"
check_dir "$WORKSPACE/knowledge/vault" "knowledge/vault"
check_dir "$WORKSPACE/users" "users"
check_dir "$WORKSPACE/groups" "groups"
check_dir "$WORKSPACE/conversations" "conversations"
check_dir "$WORKSPACE/admin" "admin"
if [ -e "$WORKSPACE/sessions" ] || [ -L "$WORKSPACE/sessions" ]; then
  fail "legacy workspace/sessions must be removed"
else
  ok "legacy workspace/sessions removed"
fi
if check_file_exists "$WORKSPACE/admin/permissions.md" "permissions"; then
  check_file_contains "$WORKSPACE/admin/permissions.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "agent operating contract, not a security sandbox" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "Platform + Platform User ID" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`operator\`" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`admin\`" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`member\`" "permissions"
fi
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions template"
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "Only \`operator\` and \`admin\` may edit this file" "permissions template"
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`Scope\` is a human-readable boundary" "permissions template"
if check_file_exists "$WORKSPACE/admin/knowledge-feedback.md" "knowledge feedback"; then
  check_file_contains "$WORKSPACE/admin/knowledge-feedback.md" "| Time | Platform | Chat ID | Platform User ID | Identity Key | Name | Topic | Feedback | Evidence | Status | Admin Notes |" "knowledge feedback"
fi
check_file_contains "$ROOT/.skills/knot-setup/references/knowledge-feedback.template.md" "| Time | Platform | Chat ID | Platform User ID | Identity Key | Name | Topic | Feedback | Evidence | Status | Admin Notes |" "knowledge feedback template"
if check_file_exists "$WORKSPACE/admin/backup-policy.md" "backup policy"; then
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "committed and pushed by a Codex app" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "customer-controlled git remote" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "remote \`backup\`" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "realraelrr/knot-agent" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "git add -f" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "Never use broad \`git add -A\`" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "bootstrap/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "bootstrap/knot-backup.sh" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "runtime/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "components/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "local secrets" "backup policy"
  check_file_not_contains "$WORKSPACE/admin/backup-policy.md" "legacy" "backup policy"
  check_file_not_contains "$WORKSPACE/admin/backup-policy.md" "- knowledge/" "backup policy"
fi
check_file_not_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "legacy" "backup policy template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "- knowledge/" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "bootstrap/" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "bootstrap/knot-backup.sh" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "same URL as \`origin\` or \`scaffold\`" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "bash bootstrap/knot-backup.sh" "backup automation template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "duplicate origin/scaffold remote" "backup automation template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "legacy" "backup automation template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "- knowledge/" "backup automation template"
check_backup_remote
run_helper_smoke_tests
check_dir "$ROOT/runtime" "runtime"
check_dir "$WORKSPACE/.state/tasks" ".state/tasks"

if [ -n "$PLATFORMS" ]; then
  printf '\nPlatforms\n'
  warn "platform checks validate local files and required env presence only; credential validity and /whoami authorization require live IM verification"
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
