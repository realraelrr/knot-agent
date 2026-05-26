# shellcheck shell=bash

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1: $(command -v "$1")"
  else
    fail "$1 command not found"
  fi
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
      if bash "$ROOT/bin/knot-runtime-check.sh" --root "$ROOT" --platform "$platform"; then
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

check_component_ref() {
  local label="$1"
  local dir="$2"
  local expected="$3"
  local current

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

check_component_refs_from_lock() {
  check_file_exists "$COMPONENT_LOCK" "component lockfile" || return
  component_lock_validate "$COMPONENT_LOCK" : || return
  component_lock_each_row "$COMPONENT_LOCK" check_component_lock_ref_row
}

check_component_lock_ref_row() {
  local name="$1"
  local _repo="$2"
  local ref="$3"
  local path="$4"

  check_component_ref "$name component" "$ROOT/$path" "$ref"
}

run_local_environment_checks() {
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
}

run_skill_link_checks() {
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
  check_skill_link "knot-collaborator-profile" "$ROOT/.skills/knot-collaborator-profile"
  check_skill_link "wiki-ingest" "$ROOT/components/obsidian-wiki/.skills/wiki-ingest"
  check_skill_link "wiki-query" "$ROOT/components/obsidian-wiki/.skills/wiki-query"
  check_skill_link "wiki-status" "$ROOT/components/obsidian-wiki/.skills/wiki-status"
}

run_component_checks() {
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
  check_file_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "current direct-user workspace" "web-ppt skill"
  check_file_not_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "current session" "web-ppt skill"
  check_component_refs_from_lock
}

run_workspace_structure_checks() {
  printf '\nWorkspace\n'
  check_file_contains "$ROOT/.gitignore" ".state/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "workspace/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "runtime/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "components/" ".gitignore"

  check_executable "$ROOT/bin/knot-workspace.sh" "knot-workspace helper"
  check_executable "$ROOT/bin/knot-install.sh" "knot-install helper"
  check_executable "$ROOT/bin/knot-audit.sh" "knot-audit helper"
  check_executable "$ROOT/bin/knot-attachment.sh" "knot-attachment helper"
  check_executable "$ROOT/bin/knot-deliver.sh" "knot-deliver helper"
  check_executable "$ROOT/bin/knot-backup.sh" "knot-backup helper"
  check_executable "$ROOT/bin/knot-runtime-check.sh" "knot-runtime-check helper"
  check_executable "$ROOT/bin/knot-im-smoke-plan.sh" "IM smoke plan helper"
  check_executable "$ROOT/bin/knot-permission-smoke.sh" "permission smoke helper"
  check_file_exists "$ROOT/lib/knot/core.sh" "Knot core shell library"
  check_executable "$ROOT/tests/integration.sh" "integration smoke tests"
  check_operations_docs
  check_file_exists "$ROOT/docs/ops/im-smoke-sop.md" "IM smoke SOP"
  check_file_exists "$ROOT/docs/security/security-model.md" "security model"
  check_file_exists "$ROOT/docs/schemas/audit-event.schema.json" "audit event schema"

  check_dir "$WORKSPACE/knowledge/raw" "knowledge/raw"
  check_dir "$WORKSPACE/knowledge/processed" "knowledge/processed"
  check_dir "$WORKSPACE/knowledge/vault" "knowledge/vault"
  check_dir "$WORKSPACE/users" "users"
  check_dir "$WORKSPACE/groups" "groups"
  check_dir "$WORKSPACE/conversations" "conversations"
  check_dir "$WORKSPACE/admin" "admin"
  check_dir "$ROOT/runtime" "runtime"
  check_dir "$WORKSPACE/.state/tasks" ".state/tasks"
}

run_workspace_contract_checks() {
  printf '\nWorkspace contracts\n'
  if check_file_exists "$WORKSPACE/admin/permissions.md" "permissions"; then
    check_file_contains "$WORKSPACE/admin/permissions.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions"
    check_file_contains "$WORKSPACE/admin/permissions.md" "\`operator\`" "permissions"
    check_file_contains "$WORKSPACE/admin/permissions.md" "\`admin\`" "permissions"
    check_file_contains "$WORKSPACE/admin/permissions.md" "\`member\`" "permissions"
    check_file_contains_doc_lint "$WORKSPACE/admin/permissions.md" "agent operating contract, not a security sandbox" "permissions"
    check_file_contains_doc_lint "$WORKSPACE/admin/permissions.md" "Platform + Platform User ID" "permissions"
  fi
  if check_file_exists "$WORKSPACE/admin/knowledge-feedback.md" "knowledge feedback"; then
    check_file_contains "$WORKSPACE/admin/knowledge-feedback.md" "$KNOWLEDGE_FEEDBACK_HEADER" "knowledge feedback"
  fi
  if check_file_exists "$WORKSPACE/admin/backup-policy.md" "backup policy"; then
    check_file_contains "$WORKSPACE/admin/backup-policy.md" "remote \`backup\`" "backup policy"
    check_file_contains "$WORKSPACE/admin/backup-policy.md" "bin/knot-backup.sh" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "committed and pushed by a Codex app" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "customer-controlled git remote" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "realraelrr/knot-agent" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "git add -f" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "Never use broad \`git add -A\`" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "bin/" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "runtime/" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "components/" "backup policy"
    check_file_contains_doc_lint "$WORKSPACE/admin/backup-policy.md" "local secrets" "backup policy"
  fi
}

run_runtime_checks() {
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
}
