# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

style_lifecycle_root="$TMP_PARENT/style-lifecycle-root"
mkdir -p "$style_lifecycle_root/workspace/admin" \
  "$style_lifecycle_root/workspace/users/style-user" \
  "$style_lifecycle_root/workspace/users/style-user/.knot"

valid_style="$style_lifecycle_root/workspace/users/style-user/style.md"
cat > "$valid_style" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Working Style

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

if lint_output="$(bash "$ROOT/bin/knot-working-style-lint.sh" lint \
  --root "$style_lifecycle_root" \
  --style "$valid_style" 2>&1)" &&
  printf '%s\n' "$lint_output" | grep -Fq "schema=ok"; then
  ok "working style lint accepts valid schema"
else
  fail "working style lint rejected valid schema: ${lint_output:-}"
fi

invalid_style="$style_lifecycle_root/workspace/users/style-user/invalid.md"
cat > "$invalid_style" <<'EOF'
---
version: 1
updated: 2026-01-01
extra: no
---
# Working Style

## Secrets
- password: should-not-land
EOF

if bash "$ROOT/bin/knot-working-style-lint.sh" lint \
  --root "$style_lifecycle_root" \
  --style "$invalid_style" >/dev/null 2>&1; then
  fail "working style lint allowed invalid schema"
else
  ok "working style lint rejects invalid schema"
fi

secret_style="$style_lifecycle_root/workspace/users/style-user/secret.md"
cat > "$secret_style" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Working Style

## Communication
- api_key: should-not-land
EOF

if bash "$ROOT/bin/knot-working-style-lint.sh" lint \
  --root "$style_lifecycle_root" \
  --style "$secret_style" >/dev/null 2>&1; then
  fail "working style lint allowed secrets-looking content"
else
  ok "working style lint rejects secrets-looking content"
fi

source_block_style="$style_lifecycle_root/workspace/users/style-user/source-block.md"
cat > "$source_block_style" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Working Style

## Communication
```transcript
raw history should not land
```
EOF

if bash "$ROOT/bin/knot-working-style-lint.sh" lint \
  --root "$style_lifecycle_root" \
  --style "$source_block_style" >/dev/null 2>&1; then
  fail "working style lint allowed raw transcript or source document blocks"
else
  ok "working style lint rejects raw transcript and source-document blocks"
fi

mixed_preference_style="$style_lifecycle_root/workspace/users/style-user/mixed-preference.md"
cat > "$mixed_preference_style" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Working Style

## Communication
- Prefers concise answers.
- Prefers detailed answers.
EOF

if mixed_preference_output="$(bash "$ROOT/bin/knot-working-style-lint.sh" lint \
  --root "$style_lifecycle_root" \
  --style "$mixed_preference_style" 2>&1)" &&
  printf '%s\n' "$mixed_preference_output" | grep -Fq "schema=ok" &&
  ! printf '%s\n' "$mixed_preference_output" | grep -Fq "conflicts="; then
  ok "working style lint stays structural and does not emit semantic state"
else
  fail "working style lint emitted semantic state"
fi

outside_section_style="$style_lifecycle_root/workspace/users/style-user/outside-section.md"
cat > "$outside_section_style" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Working Style

- Task note outside an allowed section.
EOF
if bash "$ROOT/bin/knot-working-style-lint.sh" lint \
  --root "$style_lifecycle_root" \
  --style "$outside_section_style" >/dev/null 2>&1; then
  fail "working style lint allowed content outside fixed sections"
else
  ok "working style lint rejects content outside fixed sections"
fi

long_style="$style_lifecycle_root/workspace/users/style-user/long.md"
{
  printf '%s\n' '---' 'version: 1' 'updated: 2026-01-01' 'reviewed: 2026-01-01' '---' '# Working Style' '' '## Communication'
  printf -- '- '
  printf 'x%.0s' $(seq 1 1220)
  printf '\n'
} > "$long_style"
if long_output="$(bash "$ROOT/bin/knot-working-style-lint.sh" lint \
  --root "$style_lifecycle_root" \
  --style "$long_style" 2>&1)" &&
  printf '%s\n' "$long_output" | grep -Fq "compact_recommended=true"; then
  ok "working style lint recommends compacting near limit"
else
  fail "working style lint did not recommend compacting near limit"
fi
