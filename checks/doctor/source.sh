# shellcheck shell=bash

check_component_lock_schema() {
  check_file_exists "$COMPONENT_LOCK" "component lockfile" || return
  if component_lock_validate "$COMPONENT_LOCK" fail; then
    ok "component lock rows: $COMPONENT_LOCK_ROWS"
  fi
}

run_source_structure_checks() {
  printf '\nScaffold source\n'
  check_file_exists "$ROOT/.skills/knot-setup/references/codex-agents.template.md" "Codex global AGENTS template"
  check_file_exists "$ROOT/.skills/knot-setup/references/AGENTS.template.md" "project AGENTS template"
  check_file_exists "$ROOT/.skills/knot-setup/SKILL.md" "knot-setup skill"
  check_file_exists "$ROOT/.skills/knot-workflow/SKILL.md" "knot-workflow skill"
  check_file_exists "$ROOT/lib/knot/core.sh" "Knot core shell library"
  check_file_exists "$ROOT/lib/knot/component-lock.sh" "component lock library"
  check_file_exists "$ROOT/checks/doctor/common.sh" "doctor common checks module"
  check_file_exists "$ROOT/checks/doctor/source.sh" "doctor source checks module"
  check_file_exists "$ROOT/checks/doctor/installed.sh" "doctor installed checks module"
  check_executable "$ROOT/tests/integration.sh" "integration smoke tests"

  check_executable "$ROOT/bin/knot-audit.sh" "knot-audit helper"
  check_executable "$ROOT/bin/knot-workspace.sh" "knot-workspace helper"
  check_executable "$ROOT/bin/knot-install.sh" "knot-install helper"
  check_executable "$ROOT/bin/knot-attachment.sh" "knot-attachment helper"
  check_executable "$ROOT/bin/knot-deliver.sh" "knot-deliver helper"
  check_executable "$ROOT/bin/knot-backup.sh" "knot-backup helper"
  check_executable "$ROOT/bin/knot-runtime-check.sh" "knot-runtime-check helper"
  check_executable "$ROOT/bin/knot-im-smoke-plan.sh" "IM smoke plan helper"
  check_executable "$ROOT/bin/knot-permission-smoke.sh" "permission smoke helper"
  check_operations_docs
  check_file_exists "$ROOT/docs/im-smoke-sop.md" "IM smoke SOP"
  check_file_exists "$ROOT/docs/security-model.md" "security model"
  check_file_exists "$ROOT/docs/schemas/audit-event.schema.json" "audit event schema"

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
  check_file_contains "$ROOT/AGENTS.md" "bin/knot-workspace.sh" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "KNOT_ACTIVE_WORKSPACE" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "KNOT_GROUP_WORKSPACE" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "workspace/conversations/<platform>/chat_<hash>/" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "workspace/admin/permissions.md" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "access another user's workspace" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "bin/knot-deliver.sh" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "bin/knot-attachment.sh" "AGENTS.md"
  check_file_contains "$ROOT/AGENTS.md" "cc-connect-attachments" "AGENTS.md"
  check_file_contains "$ROOT/docs/security-model.md" "## Trust Boundaries" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "Codex session history" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "boundary event records" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## Boundary Classes" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## What Knot Prevents" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## What Knot Does Not Prevent" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## Local Secrets Policy" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## Workspace Isolation Model" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## IM Attachment Boundary" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## Admin And Operator Responsibilities" "security model"
  check_file_contains "$ROOT/docs/security-model.md" "## Enterprise Hardening Recommendations" "security model"

  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "## First Decision" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "## User-Facing Replies And Internal Protocol" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "## Routing" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "## Storage Rules" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/admin/permissions.md" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bin/knot-workspace.sh" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "KNOT_ACTIVE_WORKSPACE" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bin/knot-deliver.sh" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bin/knot-attachment.sh" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/conversations/<platform>/chat_<hash>/" "knot-workflow"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/users/<user_slug>/deliverables" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/groups/<group_slug>/deliverables" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ROOT=" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "[projects.knot_workspace]" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "CC_CONNECT_BIN=" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "components/cc-connect-local-main/cc-connect" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bin/knot-workspace.sh" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bin/knot-attachment.sh" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bin/knot-runtime-check.sh" "runtime config"
  check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ACTIVE_WORKSPACE=" "runtime config"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "## Roles" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`operator\`" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`admin\`" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`member\`" "permissions template"
  check_file_contains "$ROOT/.skills/knot-setup/references/knowledge-feedback.template.md" "$KNOWLEDGE_FEEDBACK_HEADER" "knowledge feedback template"
  check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "## Scope" "backup policy template"
  check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "## Rules" "backup policy template"
  check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "bin/knot-backup.sh" "backup policy template"
  check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "bash bin/knot-backup.sh" "backup automation template"
}

run_doc_lint_checks() {
  printf '\nDocumentation lint\n'
  check_file_contains_doc_lint "$ROOT/AGENTS.md" "visible diff" "AGENTS.md"
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
  check_file_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "Use the lightest execution weight" "knot-workflow"
  check_file_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "Default to the user-visible result" "knot-workflow"
  check_file_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "must not mention helper" "knot-workflow"
  check_file_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-ingest skill" "knot-workflow"
  check_file_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-query skill" "knot-workflow"
  check_file_contains_doc_lint "$ROOT/.skills/knot-workflow/SKILL.md" "available spreadsheet, document" "knot-workflow"
  check_file_contains_doc_lint "$ROOT/.skills/knot-setup/references/runtime-config.md" "Do not set a static agent \`work_dir\`" "runtime config"
  check_file_contains_doc_lint "$ROOT/.skills/knot-setup/references/permissions.template.md" "Only \`operator\` and \`admin\` may edit this file" "permissions template"
  check_file_contains_doc_lint "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`Scope\` is a human-readable boundary" "permissions template"
  check_file_contains_doc_lint "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "same URL as \`origin\` or \`scaffold\`" "backup policy template"
  check_file_contains_doc_lint "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "duplicate origin/scaffold remote" "backup automation template"
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
