#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
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
  local tmp_root
  local session_dir

  tmp_root="$(mktemp -d)"
  session_dir="$(bash "$ROOT/bootstrap/knot-session.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --session-key "feishu:oc:ou" --name "Smoke Test")" || {
    fail "knot-session smoke test failed"
    rm -rf "$tmp_root"
    return
  }

  if [ -d "$session_dir/deliverables" ] && grep -Fq $'session_key\tfeishu:oc:ou' "$session_dir/session.tsv"; then
    ok "knot-session smoke test"
  else
    fail "knot-session smoke test did not create expected session state"
  fi

  printf 'ok\n' > "$session_dir/deliverables/result.txt"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --kind file --path "$session_dir/deliverables/result.txt" >/dev/null; then
    ok "knot-attachment allows current session deliverable"
  else
    fail "knot-attachment rejected current session deliverable"
  fi

  mkdir -p "$tmp_root/generated"
  printf 'generated\n' > "$tmp_root/generated/image.png"
  local deliver_output
  if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --kind image --path "$tmp_root/generated/image.png")"; then
    local expected_deliverable
    expected_deliverable="$(perl -MCwd=realpath -e 'print realpath($ARGV[0])' "$session_dir/deliverables/image.png")"
    if [ -f "$session_dir/deliverables/image.png" ] &&
      printf '%s\n' "$deliver_output" | grep -Fq '```cc-connect-attachments' &&
      printf '%s\n' "$deliver_output" | grep -Fq "image: $expected_deliverable"; then
      ok "knot-deliver copies generated artifact and prints attachment block"
    else
      fail "knot-deliver did not copy generated artifact and print expected attachment block"
    fi
  else
    fail "knot-deliver rejected generated artifact"
  fi

  ln -s "$tmp_root/escaped-delivery.png" "$session_dir/deliverables/symlink.png"
  if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --kind image --path "$tmp_root/generated/image.png" --output-name "symlink.png")"; then
    if [ ! -e "$tmp_root/escaped-delivery.png" ] &&
      [ -f "$session_dir/deliverables/symlink-1.png" ] &&
      printf '%s\n' "$deliver_output" | grep -Fq "image: $(perl -MCwd=realpath -e 'print realpath($ARGV[0])' "$session_dir/deliverables/symlink-1.png")"; then
      ok "knot-deliver avoids writing through deliverables symlinks"
    else
      fail "knot-deliver wrote through or failed to avoid deliverables symlink"
    fi
  else
    fail "knot-deliver rejected delivery when output name collided with symlink"
  fi

  local other_session_dir
  other_session_dir="$(bash "$ROOT/bootstrap/knot-session.sh" --root "$tmp_root" --platform feishu --chat-id "other chat" --user-id "other user")"
  printf 'private\n' > "$other_session_dir/deliverables/private.txt"
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --kind file --path "$other_session_dir/deliverables/private.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed artifact from another IM session"
  else
    ok "knot-deliver rejects artifact from another IM session"
  fi

  printf 'external\n' > "$tmp_root/generated/external.txt"
  ln -s "$tmp_root/generated/external.txt" "$other_session_dir/deliverables/external-link.txt"
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --kind file --path "$other_session_dir/deliverables/external-link.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed symlink path from another IM session"
  else
    ok "knot-deliver rejects symlink path from another IM session"
  fi

  printf 'outside\n' > "$tmp_root/outside.txt"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --kind file --path "$tmp_root/outside.txt" >/dev/null 2>&1; then
    fail "knot-attachment allowed file outside current session"
  else
    ok "knot-attachment rejects file outside current session"
  fi

  ln -s "$tmp_root/outside.txt" "$session_dir/deliverables/leak.txt"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --kind file --path "$session_dir/deliverables/leak.txt" >/dev/null 2>&1; then
    fail "knot-attachment allowed symlink escaping current session"
  else
    ok "knot-attachment rejects symlink escaping current session"
  fi

  local unsafe_root
  unsafe_root="$(mktemp -d)"
  git -C "$unsafe_root" init >/dev/null 2>&1
  git -C "$unsafe_root" remote add backup https://github.com/realraelrr/knot-agent.git
  if bash "$ROOT/bootstrap/knot-backup.sh" --root "$unsafe_root" >/dev/null 2>&1; then
    fail "knot-backup allowed scaffold backup remote"
  else
    ok "knot-backup rejects scaffold backup remote"
  fi

  rm -rf "$tmp_root" "$unsafe_root"
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

printf 'Knot doctor\n'
printf 'Root: %s\n\n' "$ROOT"

check_cmd codex
check_macos_app Codex
check_macos_app Obsidian

printf '\nSkills\n'
check_skill_link "planning-with-files" "$ROOT/components/planning-with-files/.codex/skills/planning-with-files"
check_skill_link "docling-skill" "$ROOT/components/docling-skill"
check_skill_link "office-xlsx" "$ROOT/components/knot-skills/skills/office-xlsx"
check_skill_link "office-pptx" "$ROOT/components/knot-skills/skills/office-pptx"
check_skill_link "office-docx" "$ROOT/components/knot-skills/skills/office-docx"
check_skill_link "office-pdf" "$ROOT/components/knot-skills/skills/office-pdf"
check_skill_link "web-ppt" "$ROOT/components/knot-skills/skills/web-ppt"
check_skill_link "handoff" "$ROOT/components/knot-skills/skills/handoff"
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
check_executable "$ROOT/components/knot-skills/scripts/install-codex-skills.sh" "knot-skills installer"
check_dir "$ROOT/components/knot-skills/skills/office-xlsx" "office-xlsx source"
check_dir "$ROOT/components/knot-skills/skills/office-pptx" "office-pptx source"
check_dir "$ROOT/components/knot-skills/skills/office-docx" "office-docx source"
check_dir "$ROOT/components/knot-skills/skills/office-pdf" "office-pdf source"
check_dir "$ROOT/components/knot-skills/skills/web-ppt" "web-ppt source"
check_dir "$ROOT/components/knot-skills/skills/handoff" "handoff source"
check_file_exists "$ROOT/components/knot-skills/skills/office-docx/scripts/dotnet/OfficeDocx.Cli/OfficeDocx.Cli.csproj" "office-docx CLI project"

printf '\nWorkspace\n'
WORKSPACE="$ROOT/workspace"

check_file_contains "$ROOT/.gitignore" ".state/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "workspace/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "runtime/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "components/" ".gitignore"

check_executable "$ROOT/bootstrap/knot-session.sh" "knot-session helper"
check_executable "$ROOT/bootstrap/knot-attachment.sh" "knot-attachment helper"
check_executable "$ROOT/bootstrap/knot-deliver.sh" "knot-deliver helper"
check_executable "$ROOT/bootstrap/knot-backup.sh" "knot-backup helper"
check_executable "$ROOT/bootstrap/knot-runtime-check.sh" "knot-runtime-check helper"
check_file_contains "$ROOT/AGENTS.md" "## Thin Glue Helpers" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-session.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-attachment.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-deliver.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-backup.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-runtime-check.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Permissions" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Session Isolation" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Execution Modes" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "\`quick\`" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "\`durable\`" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "\`risky\`" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "planning-with-files" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Office Pack" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "office-xlsx" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "office-pptx" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "office-docx" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "office-pdf" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "web-ppt" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Force \`planning-with-files\` only" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "Ordinary deliverables and small multi-step" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "independent review" "AGENTS.md"
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
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Apply the permissions contract in \`AGENTS.md\`" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "apply \`AGENTS.md\` \`quick\` / \`durable\` / \`risky\` rules" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Default to the user-visible result" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-session.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-attachment.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-deliver.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-backup.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-runtime-check.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-xlsx" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-pptx" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-docx" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-pdf" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "web-ppt" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/sessions/<platform>/<chat_id>/<user_id>/deliverables" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ROOT=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "CC_CONNECT_BIN=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "components/cc-connect-local-main/cc-connect" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-session.sh" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-attachment.sh" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-runtime-check.sh" "runtime config"
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
