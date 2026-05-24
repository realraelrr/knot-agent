# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

install_root="$TMP_PARENT/install-root"
mkdir -p "$install_root/.skills/knot-setup" "$install_root/.skills/knot-workflow"
cp -R "$ROOT/bin" "$install_root/bin"
cp -R "$ROOT/lib" "$install_root/lib"
cp -R "$ROOT/checks" "$install_root/checks"
cp -R "$ROOT/.skills/knot-setup/references" "$install_root/.skills/knot-setup/references"
cp "$ROOT/AGENTS.md" "$install_root/AGENTS.md"
cp "$ROOT/components.lock" "$install_root/components.lock"
cp "$ROOT/.gitignore" "$install_root/.gitignore"
printf '%s\n' 'name: knot-workflow' > "$install_root/.skills/knot-workflow/SKILL.md"
mkdir -p \
  "$install_root/components/planning-with-files/.codex/skills/planning-with-files" \
  "$install_root/components/docling-skill/.codex/skills/docling-skill" \
  "$install_root/components/md-for-human/.codex/skills/md-for-human" \
  "$install_root/components/handoff-skill/.codex/skills/handoff"
printf '%s\n' 'name: planning-with-files' > "$install_root/components/planning-with-files/.codex/skills/planning-with-files/SKILL.md"
printf '%s\n' 'name: docling-skill' > "$install_root/components/docling-skill/.codex/skills/docling-skill/SKILL.md"
printf '%s\n' 'name: md-for-human' > "$install_root/components/md-for-human/.codex/skills/md-for-human/SKILL.md"
printf '%s\n' 'name: handoff' > "$install_root/components/handoff-skill/.codex/skills/handoff/SKILL.md"
if CODEX_HOME="$install_root/codex-home" bash "$install_root/bin/knot-install.sh" \
  --root "$install_root" \
  --skip-components \
  --skip-build \
  --skip-backup-remote \
  --skip-doctor >/dev/null; then
  if [ -d "$install_root/workspace/users" ] &&
    [ -d "$install_root/runtime" ] &&
    [ -f "$install_root/workspace/admin/permissions.md" ] &&
    [ -f "$install_root/codex-home/AGENTS.md" ] &&
    [ -x "$install_root/bin/knot-audit.sh" ] &&
    [ -x "$install_root/bin/knot-workspace.sh" ] &&
    [ -f "$install_root/lib/knot/component-lock.sh" ] &&
    [ ! -x "$install_root/lib/knot/component-lock.sh" ] &&
    [ "$(readlink "$install_root/codex-home/skills/planning-with-files")" = "$install_root/components/planning-with-files/.codex/skills/planning-with-files" ] &&
    [ "$(readlink "$install_root/codex-home/skills/docling-skill")" = "$install_root/components/docling-skill/.codex/skills/docling-skill" ] &&
    [ "$(readlink "$install_root/codex-home/skills/md-for-human")" = "$install_root/components/md-for-human/.codex/skills/md-for-human" ] &&
    [ "$(readlink "$install_root/codex-home/skills/handoff")" = "$install_root/components/handoff-skill/.codex/skills/handoff" ] &&
    [ ! -x "$install_root/lib/knot/core.sh" ]; then
    ok "knot-install smoke test creates deterministic local scaffold"
  else
    fail "knot-install smoke test missed expected scaffold files"
  fi
else
  fail "knot-install smoke test failed"
fi

repair_root="$TMP_PARENT/repair-root"
mkdir -p "$repair_root/.skills/knot-setup" \
  "$repair_root/.skills/knot-workflow" \
  "$repair_root/workspace/admin" \
  "$repair_root/codex-home"
cp -R "$ROOT/bin" "$repair_root/bin"
cp -R "$ROOT/lib" "$repair_root/lib"
cp -R "$ROOT/checks" "$repair_root/checks"
cp -R "$ROOT/.skills/knot-setup/references" "$repair_root/.skills/knot-setup/references"
cp "$ROOT/AGENTS.md" "$repair_root/AGENTS.md"
cp "$ROOT/components.lock" "$repair_root/components.lock"
cp "$ROOT/.gitignore" "$repair_root/.gitignore"
printf '%s\n' 'name: knot-workflow' > "$repair_root/.skills/knot-workflow/SKILL.md"
printf '%s\n' 'custom global instructions' > "$repair_root/codex-home/AGENTS.md"
printf '%s\n' 'custom permissions' > "$repair_root/workspace/admin/permissions.md"
printf '%s\n' 'custom feedback' > "$repair_root/workspace/admin/knowledge-feedback.md"
printf '%s\n' 'custom backup policy' > "$repair_root/workspace/admin/backup-policy.md"

if CODEX_HOME="$repair_root/codex-home" bash "$repair_root/bin/knot-install.sh" \
  --root "$repair_root" \
  --skip-components \
  --skip-build \
  --skip-backup-remote \
  --skip-doctor >/dev/null &&
  grep -Fq 'custom global instructions' "$repair_root/codex-home/AGENTS.md" &&
  grep -Fq 'custom permissions' "$repair_root/workspace/admin/permissions.md" &&
  grep -Fq 'custom feedback' "$repair_root/workspace/admin/knowledge-feedback.md" &&
  grep -Fq 'custom backup policy' "$repair_root/workspace/admin/backup-policy.md"; then
  ok "knot-install preserves existing global instructions and admin files"
else
  fail "knot-install overwrote existing global instructions or admin files"
fi

: > "$repair_root/codex-home/AGENTS.md"
if CODEX_HOME="$repair_root/codex-home" bash "$repair_root/bin/knot-install.sh" \
  --root "$repair_root" \
  --skip-components \
  --skip-build \
  --skip-backup-remote \
  --skip-doctor >/dev/null &&
  [ ! -s "$repair_root/codex-home/AGENTS.md" ]; then
  ok "knot-install preserves existing empty global instructions file"
else
  fail "knot-install overwrote existing empty global instructions file"
fi

LOCK_CASE_INDEX=0

write_lock_with_extra_row() {
  local path="$1"
  local row="$2"

  cp "$ROOT/components.lock" "$path"
  printf '%s\n' "$row" >> "$path"
}

expect_installer_rejects_lock() {
  local label="$1"
  local expected="$2"
  local lock_file="$3"
  local lock_root
  local output

  LOCK_CASE_INDEX=$((LOCK_CASE_INDEX + 1))
  lock_root="$TMP_PARENT/lock-case-$LOCK_CASE_INDEX"
  cp -R "$install_root" "$lock_root"
  cp "$lock_file" "$lock_root/components.lock"

  if output="$(CODEX_HOME="$lock_root/codex-home" bash "$lock_root/bin/knot-install.sh" \
    --root "$lock_root" \
    --skip-build \
    --skip-backup-remote \
    --skip-doctor 2>&1)"; then
    fail "knot-install allowed $label"
  elif printf '%s\n' "$output" | grep -Fq "$expected"; then
    ok "knot-install rejects $label"
  else
    fail "knot-install rejected $label for wrong reason: $output"
  fi

  if [ -e "$lock_root/components/new-component" ]; then
    fail "knot-install mutated components before rejecting $label"
  fi
}

expect_doctor_rejects_lock() {
  local label="$1"
  local expected="$2"
  local lock_file="$3"
  local output

  if output="$(env \
    ROOT="$ROOT" \
    COMPONENT_LOCK="$lock_file" \
    STRICT_DOCS=0 \
    FAILURES=0 \
    WARNINGS=0 \
    bash -c '
      set -u
      . "$ROOT/checks/doctor/common.sh"
      . "$ROOT/lib/knot/component-lock.sh"
      . "$ROOT/checks/doctor/source.sh"
      check_component_lock_schema
      [ "$FAILURES" -eq 0 ]
    ' 2>&1)"; then
    fail "doctor allowed $label"
  elif printf '%s\n' "$output" | grep -Fq "$expected"; then
    ok "doctor rejects $label"
  else
    fail "doctor rejected $label for wrong reason: $output"
  fi
}

expect_installer_rejects_lock_without_clone() {
  local label="$1"
  local expected="$2"
  local lock_file="$3"
  local lock_root
  local output

  LOCK_CASE_INDEX=$((LOCK_CASE_INDEX + 1))
  lock_root="$TMP_PARENT/lock-case-$LOCK_CASE_INDEX"
  cp -R "$install_root" "$lock_root"
  cp "$lock_file" "$lock_root/components.lock"

  if output="$(CODEX_HOME="$lock_root/codex-home" bash "$lock_root/bin/knot-install.sh" \
    --root "$lock_root" \
    --skip-components \
    --skip-build \
    --skip-backup-remote \
    --skip-doctor 2>&1)"; then
    fail "knot-install --skip-components allowed $label"
  elif printf '%s\n' "$output" | grep -Fq "$expected"; then
    ok "knot-install --skip-components rejects $label"
  else
    fail "knot-install --skip-components rejected $label for wrong reason: $output"
  fi
}

lock_case="$TMP_PARENT/lock-path-traversal.tsv"
write_lock_with_extra_row "$lock_case" $'bad\thttps://github.com/example/bad\t0000000000000000000000000000000000000000\tcomponents/../runtime/escape'
expect_installer_rejects_lock "component lock path traversal" "component lock path must be components/<safe-dir>" "$lock_case"
expect_doctor_rejects_lock "component lock path traversal" "component lock path must be components/<safe-dir>" "$lock_case"

lock_case="$TMP_PARENT/lock-empty-field.tsv"
write_lock_with_extra_row "$lock_case" $'bad\t\t0000000000000000000000000000000000000000\tcomponents/new-component'
expect_installer_rejects_lock "empty component lock field" "missing repo" "$lock_case"
expect_doctor_rejects_lock "empty component lock field" "missing repo" "$lock_case"

lock_case="$TMP_PARENT/lock-extra-field.tsv"
write_lock_with_extra_row "$lock_case" $'bad\thttps://github.com/example/bad\t0000000000000000000000000000000000000000\tcomponents/new-component\textra'
expect_installer_rejects_lock "extra component lock field" "too many fields" "$lock_case"
expect_doctor_rejects_lock "extra component lock field" "too many fields" "$lock_case"

lock_case="$TMP_PARENT/lock-short-sha.tsv"
write_lock_with_extra_row "$lock_case" $'bad\thttps://github.com/example/bad\tabc123\tcomponents/new-component'
expect_installer_rejects_lock "short component lock SHA" "full 40-character SHA" "$lock_case"
expect_doctor_rejects_lock "short component lock SHA" "full 40-character SHA" "$lock_case"

lock_case="$TMP_PARENT/lock-non-github.tsv"
write_lock_with_extra_row "$lock_case" $'bad\thttps://example.com/example/bad\t0000000000000000000000000000000000000000\tcomponents/new-component'
expect_installer_rejects_lock "non-GitHub component lock repo" "GitHub HTTPS URL" "$lock_case"
expect_doctor_rejects_lock "non-GitHub component lock repo" "GitHub HTTPS URL" "$lock_case"
expect_installer_rejects_lock_without_clone "non-GitHub component lock repo" "GitHub HTTPS URL" "$lock_case"

lock_case="$TMP_PARENT/lock-duplicate-name.tsv"
write_lock_with_extra_row "$lock_case" $'docling-skill\thttps://github.com/example/bad\t0000000000000000000000000000000000000000\tcomponents/new-component'
expect_installer_rejects_lock "duplicate component lock name" "duplicate name" "$lock_case"
expect_doctor_rejects_lock "duplicate component lock name" "duplicate name" "$lock_case"

lock_case="$TMP_PARENT/lock-duplicate-path.tsv"
write_lock_with_extra_row "$lock_case" $'new-component\thttps://github.com/example/bad\t0000000000000000000000000000000000000000\tcomponents/docling-skill'
expect_installer_rejects_lock "duplicate component lock path" "duplicate path" "$lock_case"
expect_doctor_rejects_lock "duplicate component lock path" "duplicate path" "$lock_case"

lock_case="$TMP_PARENT/lock-missing-required.tsv"
cat > "$lock_case" <<'EOF'
name	repo	ref	path
docling-skill	https://github.com/example/docling-skill	0000000000000000000000000000000000000000	components/docling-skill
EOF
expect_installer_rejects_lock "component lock missing required entries" "component lock missing required path" "$lock_case"
expect_doctor_rejects_lock "component lock missing required entries" "component lock missing required path" "$lock_case"
