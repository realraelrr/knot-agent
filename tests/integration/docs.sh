# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Depends on integration-common.sh creating TMP_PARENT.
run_source_doc_checks() {
  local root="$1"
  local strict_docs="$2"

  env \
    ROOT="$root" \
    STRICT_DOCS="$strict_docs" \
    FAILURES=0 \
    WARNINGS=0 \
    KNOWLEDGE_FEEDBACK_HEADER='| Time | Platform | Chat ID | Platform User ID | Identity Key | Name | Topic | Feedback | Evidence | Diff | Status | Execution | Admin Notes |' \
    bash -c '
      set -u
      . "$ROOT/checks/doctor/common.sh"
      . "$ROOT/checks/doctor/source.sh"
      run_contract_checks
      run_doc_lint_checks
      [ "$FAILURES" -eq 0 ]
    '
}

run_workspace_doc_checks() {
  local root="$1"
  local strict_docs="$2"

  env \
    ROOT="$root" \
    WORKSPACE="$root/workspace" \
    STRICT_DOCS="$strict_docs" \
    FAILURES=0 \
    WARNINGS=0 \
    KNOWLEDGE_FEEDBACK_HEADER='| Time | Platform | Chat ID | Platform User ID | Identity Key | Name | Topic | Feedback | Evidence | Diff | Status | Execution | Admin Notes |' \
    bash -c '
      set -u
      . "$ROOT/checks/doctor/common.sh"
      . "$ROOT/checks/doctor/installed.sh"
      run_workspace_contract_checks
      [ "$FAILURES" -eq 0 ]
    '
}

doc_root="$TMP_PARENT/doc-contract-root"
mkdir -p \
  "$doc_root/checks/doctor" \
  "$doc_root/.skills/knot-setup/references" \
  "$doc_root/.skills/knot-knowledge" \
  "$doc_root/.skills/knot-delivery" \
  "$doc_root/.skills/working-style" \
  "$doc_root/.skills/knot-workflow" \
  "$doc_root/docs/ops" \
  "$doc_root/docs/schemas" \
  "$doc_root/docs/security" \
  "$doc_root/workspace/admin"
cp "$ROOT/checks/doctor/common.sh" "$doc_root/checks/doctor/common.sh"
cp "$ROOT/checks/doctor/source.sh" "$doc_root/checks/doctor/source.sh"
cp "$ROOT/checks/doctor/installed.sh" "$doc_root/checks/doctor/installed.sh"
cp "$ROOT/AGENTS.md" "$doc_root/AGENTS.md"
cp "$ROOT/.skills/knot-knowledge/SKILL.md" "$doc_root/.skills/knot-knowledge/SKILL.md"
cp "$ROOT/.skills/knot-delivery/SKILL.md" "$doc_root/.skills/knot-delivery/SKILL.md"
cp "$ROOT/.skills/working-style/SKILL.md" "$doc_root/.skills/working-style/SKILL.md"
cp "$ROOT/.skills/knot-workflow/SKILL.md" "$doc_root/.skills/knot-workflow/SKILL.md"
cp "$ROOT/.skills/knot-setup/references/"*.md "$doc_root/.skills/knot-setup/references/"
cp "$ROOT/docs/ops/im-smoke-sop.md" "$doc_root/docs/ops/im-smoke-sop.md"
cp "$ROOT/docs/ops/deployment-profiles.md" "$doc_root/docs/ops/deployment-profiles.md"
cp "$ROOT/docs/schemas/audit-event-semantics.md" "$doc_root/docs/schemas/audit-event-semantics.md"
cp "$ROOT/docs/security/security-model.md" "$doc_root/docs/security/security-model.md"
cp "$ROOT/.skills/knot-setup/references/permissions.template.md" "$doc_root/workspace/admin/permissions.md"
cp "$ROOT/.skills/knot-setup/references/knowledge-feedback.template.md" "$doc_root/workspace/admin/knowledge-feedback.md"
cp "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "$doc_root/workspace/admin/backup-policy.md"

sed 's/visible diff/human-reviewable diff/' "$doc_root/AGENTS.md" > "$doc_root/AGENTS.md.tmp"
mv "$doc_root/AGENTS.md.tmp" "$doc_root/AGENTS.md"
sed 's/Default to the user-visible result. Normal replies must not mention helper or/Reply with the user-visible outcome first. Normal replies must not expose helper or/' "$doc_root/.skills/knot-workflow/SKILL.md" > "$doc_root/.skills/knot-workflow/SKILL.md.tmp"
mv "$doc_root/.skills/knot-workflow/SKILL.md.tmp" "$doc_root/.skills/knot-workflow/SKILL.md"
sed 's/Do not set a static agent `work_dir`/Never configure a fixed agent `work_dir`/' "$doc_root/.skills/knot-setup/references/runtime-config.md" > "$doc_root/.skills/knot-setup/references/runtime-config.md.tmp"
mv "$doc_root/.skills/knot-setup/references/runtime-config.md.tmp" "$doc_root/.skills/knot-setup/references/runtime-config.md"
sed 's/duplicate origin\/scaffold remote/same URL as an unsafe remote/' "$doc_root/.skills/knot-setup/references/daily-backup-automation.template.md" > "$doc_root/.skills/knot-setup/references/daily-backup-automation.template.md.tmp"
mv "$doc_root/.skills/knot-setup/references/daily-backup-automation.template.md.tmp" "$doc_root/.skills/knot-setup/references/daily-backup-automation.template.md"
sed 's/agent operating contract, not a security sandbox/clear authorization contract, not process isolation/' "$doc_root/workspace/admin/permissions.md" > "$doc_root/workspace/admin/permissions.md.tmp"
mv "$doc_root/workspace/admin/permissions.md.tmp" "$doc_root/workspace/admin/permissions.md"
sed 's/committed and pushed by a Codex app/committed and pushed through a Codex app/' "$doc_root/workspace/admin/backup-policy.md" > "$doc_root/workspace/admin/backup-policy.md.tmp"
mv "$doc_root/workspace/admin/backup-policy.md.tmp" "$doc_root/workspace/admin/backup-policy.md"

if output="$(run_source_doc_checks "$doc_root" 0 2>&1)" &&
  printf '%s\n' "$output" | grep -Fq 'WARN AGENTS.md missing advisory text: visible diff'; then
  ok "document wording changes are advisory outside strict-docs mode"
else
  fail "document wording changes should only warn outside strict-docs mode: $output"
fi

if run_source_doc_checks "$doc_root" 1 >/dev/null 2>&1; then
  fail "strict-docs allowed altered advisory wording"
else
  ok "strict-docs rejects altered advisory wording"
fi

if output="$(run_workspace_doc_checks "$doc_root" 0 2>&1)" &&
  printf '%s\n' "$output" | grep -Fq 'WARN permissions missing advisory text: agent operating contract, not a security sandbox'; then
  ok "installed document wording changes are advisory"
else
  fail "installed document wording changes should only warn: $output"
fi

if run_workspace_doc_checks "$doc_root" 1 >/dev/null 2>&1; then
  fail "strict-docs allowed altered installed advisory wording"
else
  ok "strict-docs rejects altered installed advisory wording"
fi

permissions_before="$(mktemp "$TMP_PARENT/permissions-before.XXXXXX")"
cp "$doc_root/workspace/admin/permissions.md" "$permissions_before"
sed 's/| Example Admin | admin | knowledge |/| Example Admin | owner | knowledge |/' "$permissions_before" > "$doc_root/workspace/admin/permissions.md"
if run_workspace_doc_checks "$doc_root" 0 >/dev/null 2>&1; then
  fail "permissions schema allowed unknown role"
else
  ok "permissions schema rejects unknown role"
fi
cp "$permissions_before" "$doc_root/workspace/admin/permissions.md"

cat >>"$doc_root/workspace/admin/permissions.md" <<'EOF'
| Duplicate | duplicate | feishu | ou_duplicate | duplicate-group | oc_duplicate | feishu:user:duplicate | Duplicate | member | session | duplicate test |
| Duplicate | duplicate | feishu | ou_duplicate | duplicate-group | oc_duplicate | feishu:user:duplicate | Duplicate | member | session | duplicate test |
EOF
if run_workspace_doc_checks "$doc_root" 0 >/dev/null 2>&1; then
  fail "permissions schema allowed duplicate actor context"
else
  ok "permissions schema rejects duplicate actor context"
fi
cp "$permissions_before" "$doc_root/workspace/admin/permissions.md"
