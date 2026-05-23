# shellcheck shell=bash

check_component_lock_schema() {
  local line
  local component_dir
  local rows=0
  local header_seen=0
  local seen_names=" "
  local seen_paths=" "
  local required_path
  local tab=$'\t'

  check_file_exists "$COMPONENT_LOCK" "component lockfile" || return

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
    esac

    if [ "$line" = "name${tab}repo${tab}ref${tab}path" ]; then
      if [ "$header_seen" -eq 1 ]; then
        fail "component lock contains duplicate header"
      fi
      header_seen=1
      continue
    fi

    parse_component_lock_line "$line" || continue
    rows=$((rows + 1))
    [ -n "$LOCK_NAME" ] || fail "component lock row missing name"
    [ -n "$LOCK_REPO" ] || fail "component lock row missing repo: $LOCK_NAME"
    [ -n "$LOCK_REF" ] || fail "component lock row missing ref: $LOCK_NAME"
    [ -n "$LOCK_PATH" ] || fail "component lock row missing path: $LOCK_NAME"

    case "$LOCK_NAME" in
      *[!A-Za-z0-9._-]*|""|.*|*..*) fail "component lock name must be a safe identifier: $LOCK_NAME" ;;
    esac

    case "$LOCK_REPO" in
      https://github.com/*) ;;
      *) fail "component lock repo must be a GitHub HTTPS URL: $LOCK_NAME" ;;
    esac

    case "$LOCK_REF" in
      *[!0-9a-f]*|"") fail "component lock ref must be a lowercase full SHA: $LOCK_NAME" ;;
      *)
        if [ "${#LOCK_REF}" -ne 40 ]; then
          fail "component lock ref must be a full 40-character SHA: $LOCK_NAME"
        fi
        ;;
    esac

    case "$LOCK_PATH" in
      components/*) ;;
      *) fail "component lock path must stay under components/: $LOCK_NAME" ;;
    esac

    component_dir="${LOCK_PATH#components/}"
    case "$component_dir" in
      ""|*/*|.*|*..*|*[!A-Za-z0-9._-]*) fail "component lock path must be components/<safe-dir>: $LOCK_NAME" ;;
    esac

    case "$seen_names" in
      *" $LOCK_NAME "*) fail "component lock duplicate name: $LOCK_NAME" ;;
      *) seen_names="${seen_names}${LOCK_NAME} " ;;
    esac

    case "$seen_paths" in
      *" $LOCK_PATH "*) fail "component lock duplicate path: $LOCK_PATH" ;;
      *) seen_paths="${seen_paths}${LOCK_PATH} " ;;
    esac
  done < "$COMPONENT_LOCK"

  if [ "$header_seen" -eq 0 ]; then
    fail "component lock header missing"
  fi

  if [ "$rows" -gt 0 ]; then
    ok "component lock rows: $rows"
  else
    fail "component lock has no component rows"
  fi

  for required_path in $REQUIRED_COMPONENT_PATHS; do
    case "$seen_paths" in
      *" $required_path "*) ;;
      *) fail "component lock missing required path: $required_path" ;;
    esac
  done
}

run_source_structure_checks() {
  printf '\nScaffold source\n'
  check_file_exists "$ROOT/.skills/knot-setup/references/codex-agents.template.md" "Codex global AGENTS template"
  check_file_exists "$ROOT/.skills/knot-setup/references/AGENTS.template.md" "project AGENTS template"
  check_file_exists "$ROOT/.skills/knot-setup/SKILL.md" "knot-setup skill"
  check_file_exists "$ROOT/.skills/knot-workflow/SKILL.md" "knot-workflow skill"
  check_file_exists "$ROOT/bootstrap/lib.sh" "bootstrap shell library"
  check_file_exists "$ROOT/bootstrap/doctor/common.sh" "doctor common checks module"
  check_file_exists "$ROOT/bootstrap/doctor/source.sh" "doctor source checks module"
  check_file_exists "$ROOT/bootstrap/doctor/installed.sh" "doctor installed checks module"
  check_executable "$ROOT/tests/integration.sh" "integration smoke tests"

  check_executable "$ROOT/bootstrap/knot-workspace.sh" "knot-workspace helper"
  check_executable "$ROOT/bootstrap/knot-install.sh" "knot-install helper"
  check_executable "$ROOT/bootstrap/knot-attachment.sh" "knot-attachment helper"
  check_executable "$ROOT/bootstrap/knot-deliver.sh" "knot-deliver helper"
  check_executable "$ROOT/bootstrap/knot-backup.sh" "knot-backup helper"
  check_executable "$ROOT/bootstrap/knot-runtime-check.sh" "knot-runtime-check helper"
  check_executable "$ROOT/bootstrap/knot-im-smoke-plan.sh" "IM smoke plan helper"
  check_executable "$ROOT/bootstrap/knot-permission-smoke.sh" "permission smoke helper"
  check_file_exists "$ROOT/docs/im-smoke-sop.md" "IM smoke SOP"

  check_file_contains "$ROOT/.gitignore" ".state/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "workspace/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "runtime/" ".gitignore"
  check_file_contains "$ROOT/.gitignore" "components/" ".gitignore"
  check_component_lock_schema
}

run_contract_checks() {
  printf '\nContracts\n'
  check_file_contains "$ROOT/AGENTS.md" "## Layout" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Workflow" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Active Workspaces" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Authorization" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Knowledge" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "## Delivery" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-workspace.sh" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "KNOT_ACTIVE_WORKSPACE" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "KNOT_GROUP_WORKSPACE" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "workspace/conversations/<platform>/<chat_id>/" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "workspace/admin/permissions.md" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "access another user's workspace" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "visible diff" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-deliver.sh" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-attachment.sh" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "cc-connect-attachments" "AGENTS.md"

  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Use the lightest execution weight" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Default to the user-visible result" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "must not mention helper" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/admin/permissions.md" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-workspace.sh" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "KNOT_ACTIVE_WORKSPACE" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-deliver.sh" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-attachment.sh" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/conversations/<platform>/<chat_id>/" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-ingest skill" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-query skill" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available spreadsheet, document" "knot-workflow"

  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/users/<user_slug>/deliverables" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/groups/<group_slug>/deliverables" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ROOT=" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "[projects.knot_workspace]" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "Do not set a static agent \`work_dir\`" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "CC_CONNECT_BIN=" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "components/cc-connect-local-main/cc-connect" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-workspace.sh" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-attachment.sh" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-runtime-check.sh" "runtime config"
  check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ACTIVE_WORKSPACE=" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "Only \`operator\` and \`admin\` may edit this file" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`Scope\` is a human-readable boundary" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/knowledge-feedback.template.md" "$KNOWLEDGE_FEEDBACK_HEADER" "knowledge feedback template"
  check_file_not_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "- knowledge/" "backup policy template"
  check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "same URL as \`origin\` or \`scaffold\`" "backup policy template"
  check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "duplicate origin/scaffold remote" "backup automation template"
  check_file_not_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "- knowledge/" "backup automation template"
}

run_doc_lint_checks() {
  printf '\nDocumentation lint\n'
  check_file_not_contains_doc_lint "$ROOT/AGENTS.md" "## Execution Modes" "AGENTS.md"
  check_file_not_contains_doc_lint "$ROOT/AGENTS.md" "## Backup Automation" "AGENTS.md"
  check_file_not_contains_doc_lint "$ROOT/AGENTS.md" "## Skill Packs" "AGENTS.md"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "office-xlsx" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "office-pptx" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "office-docx" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "office-pdf" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "web-ppt" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "md-for-human" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "docling-skill" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "wiki-ingest" "knot-workflow"
  check_file_not_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "wiki-query" "knot-workflow"
  check_file_contains_doc_lint "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "bootstrap/knot-backup.sh" "backup policy template"
  check_file_contains_doc_lint "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "bash bootstrap/knot-backup.sh" "backup automation template"
  check_file_contains_doc_lint "$ROOT/docs/im-smoke-sop.md" "Pairwise Matrix" "IM smoke SOP"
  check_file_contains_doc_lint "$ROOT/docs/im-smoke-sop.md" "Automated Permission Gate" "IM smoke SOP"
  check_file_contains_doc_lint "$ROOT/docs/im-smoke-sop.md" "Manual Permission Checks" "IM smoke SOP"
  check_file_contains_doc_lint "$ROOT/docs/im-smoke-sop.md" "High-risk checks must pass on every platform" "IM smoke SOP"
}

run_scaffold_only_checks() {
  run_source_structure_checks
  run_contract_checks
  run_doc_lint_checks
  run_smoke_checks
}
