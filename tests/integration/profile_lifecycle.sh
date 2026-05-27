# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

profile_lifecycle_root="$TMP_PARENT/profile-lifecycle-root"
mkdir -p "$profile_lifecycle_root/workspace/admin" \
  "$profile_lifecycle_root/workspace/users/profile-user/collaboration" \
  "$profile_lifecycle_root/workspace/users/profile-user/.knot"

valid_profile="$profile_lifecycle_root/workspace/users/profile-user/collaboration/profile.md"
cat > "$valid_profile" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Collaborator Profile

## Communication
- Prefers concise status updates.

## Evidence And Review
- Wants exact verification commands.

## Delivery
- Wants final answers in Chinese.

## Recurring Workflows
- Often asks for architecture review.

## Avoid
- Do not include raw transcript excerpts.
EOF

if lint_output="$(bash "$ROOT/bin/knot-collaborator-profile-lint.sh" lint \
  --root "$profile_lifecycle_root" \
  --profile "$valid_profile" \
  --write-sidecar \
  --scope direct \
  --actor-user profile-user \
  --user-workspace "$profile_lifecycle_root/workspace/users/profile-user" 2>&1)" &&
  printf '%s\n' "$lint_output" | grep -Fq "schema=ok"; then
  ok "collaborator profile lint accepts valid schema"
else
  fail "collaborator profile lint rejected valid schema: ${lint_output:-}"
fi

invalid_profile="$profile_lifecycle_root/workspace/users/profile-user/collaboration/invalid.md"
cat > "$invalid_profile" <<'EOF'
---
version: 1
updated: 2026-01-01
extra: no
---
# Collaborator Profile

## Secrets
- password: should-not-land
EOF

if bash "$ROOT/bin/knot-collaborator-profile-lint.sh" lint \
  --root "$profile_lifecycle_root" \
  --profile "$invalid_profile" >/dev/null 2>&1; then
  fail "collaborator profile lint allowed invalid schema"
else
  ok "collaborator profile lint rejects invalid schema"
fi

conflict_profile="$profile_lifecycle_root/workspace/users/profile-user/collaboration/conflict.md"
cat > "$conflict_profile" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Collaborator Profile

## Communication
- Prefers concise answers.
- Prefers detailed answers.
EOF

if conflict_output="$(bash "$ROOT/bin/knot-collaborator-profile-lint.sh" lint \
  --root "$profile_lifecycle_root" \
  --profile "$conflict_profile" \
  --write-sidecar \
  --scope direct \
  --actor-user profile-user \
  --user-workspace "$profile_lifecycle_root/workspace/users/profile-user" 2>&1)" &&
  printf '%s\n' "$conflict_output" | grep -Fq "conflicts=1" &&
  [ -f "$profile_lifecycle_root/workspace/users/profile-user/.knot/collaborator-profile-conflicts.json" ] &&
  ! grep -Fq "Prefers concise answers" "$profile_lifecycle_root/workspace/users/profile-user/.knot/collaborator-profile-conflicts.json"; then
  ok "collaborator profile lint writes redacted conflict sidecar"
else
  fail "collaborator profile lint did not write redacted conflict sidecar"
fi

if bash "$ROOT/bin/knot-collaborator-profile-lint.sh" lint \
  --root "$profile_lifecycle_root" \
  --profile "$valid_profile" \
  --write-sidecar \
  --scope direct \
  --actor-user profile-user \
  --user-workspace "$profile_lifecycle_root/workspace/users/profile-user" >/dev/null &&
  [ ! -f "$profile_lifecycle_root/workspace/users/profile-user/.knot/collaborator-profile-conflicts.json" ]; then
  ok "collaborator profile lint clears stale conflict sidecar"
else
  fail "collaborator profile lint did not clear stale conflict sidecar"
fi

outside_section_profile="$profile_lifecycle_root/workspace/users/profile-user/collaboration/outside-section.md"
cat > "$outside_section_profile" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Collaborator Profile

- Task note outside an allowed section.
EOF
if bash "$ROOT/bin/knot-collaborator-profile-lint.sh" lint \
  --root "$profile_lifecycle_root" \
  --profile "$outside_section_profile" >/dev/null 2>&1; then
  fail "collaborator profile lint allowed content outside fixed sections"
else
  ok "collaborator profile lint rejects content outside fixed sections"
fi

long_profile="$profile_lifecycle_root/workspace/users/profile-user/collaboration/long.md"
{
  printf '%s\n' '---' 'version: 1' 'updated: 2026-01-01' 'reviewed: 2026-01-01' '---' '# Collaborator Profile' '' '## Communication'
  printf -- '- '
  printf 'x%.0s' $(seq 1 1220)
  printf '\n'
} > "$long_profile"
if long_output="$(bash "$ROOT/bin/knot-collaborator-profile-lint.sh" lint \
  --root "$profile_lifecycle_root" \
  --profile "$long_profile" 2>&1)" &&
  printf '%s\n' "$long_output" | grep -Fq "compact_recommended=true"; then
  ok "collaborator profile lint recommends compacting near limit"
else
  fail "collaborator profile lint did not recommend compacting near limit"
fi
