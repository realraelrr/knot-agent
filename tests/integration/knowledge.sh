# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

knowledge_root="$TMP_PARENT/knowledge-root"
knowledge_remote="$TMP_PARENT/knowledge-remote.git"
knowledge_seed="$TMP_PARENT/knowledge-seed"
mkdir -p "$knowledge_root/workspace/admin" \
  "$knowledge_root/workspace/users/member-user/work/proposal" \
  "$knowledge_root/workspace/users/admin-user" \
  "$knowledge_seed"

cat > "$knowledge_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Admin User | admin-user | feishu | ou/admin |  | oc/admin | feishu:user:admin | Admin User | admin | knowledge | smoke |
| Member User | member-user | feishu | ou/member |  | oc/member | feishu:user:member | Member User | member | session | smoke |
EOF

git -C "$knowledge_seed" init -b main >/dev/null 2>&1
mkdir -p "$knowledge_seed/concepts"
printf '%s\n' '# Wiki Index' > "$knowledge_seed/index.md"
printf '%s\n' 'approved knowledge' > "$knowledge_seed/concepts/approved.md"
git -C "$knowledge_seed" add .
git -C "$knowledge_seed" -c user.name=Test -c user.email=test@example.com commit -m "seed wiki" >/dev/null
git clone --bare "$knowledge_seed" "$knowledge_remote" >/dev/null 2>&1

if bash "$ROOT/bin/knot-knowledge.sh" sync-approved \
  --root "$knowledge_root" \
  --repo-url "$knowledge_remote" \
  --mirror "$knowledge_root/workspace/knowledge/vault" \
  --approved-ref main \
  --platform feishu \
  --user-id ou/admin \
  --identity-key feishu:user:admin \
  --actor-user admin-user >/dev/null &&
  [ -f "$knowledge_root/workspace/knowledge/vault/concepts/approved.md" ] &&
  [ "$(git -C "$knowledge_root/workspace/knowledge/vault" branch --show-current)" = "main" ]; then
  ok "knowledge helper syncs approved main mirror"
else
  fail "knowledge helper did not sync approved main mirror"
fi

if bash "$ROOT/bin/knot-knowledge.sh" sync-approved \
  --root "$knowledge_root" \
  --repo-url "$knowledge_remote" \
  --mirror "$knowledge_root/workspace/knowledge/vault" \
  --approved-ref main \
  --platform feishu \
  --user-id ou/member \
  --identity-key feishu:user:member \
  --actor-user member-user >/dev/null 2>&1; then
  fail "knowledge helper allowed member approved mirror sync"
else
  ok "knowledge helper rejects member approved mirror sync"
fi

git -C "$knowledge_seed" checkout -b proposal >/dev/null 2>&1
printf '%s\n' 'unapproved branch content' > "$knowledge_seed/concepts/unapproved.md"
git -C "$knowledge_seed" add .
git -C "$knowledge_seed" -c user.name=Test -c user.email=test@example.com commit -m "unapproved proposal" >/dev/null
git -C "$knowledge_seed" push "$knowledge_remote" proposal >/dev/null 2>&1
if bash "$ROOT/bin/knot-knowledge.sh" sync-approved \
  --root "$knowledge_root" \
  --repo-url "$knowledge_remote" \
  --mirror "$knowledge_root/workspace/knowledge/unapproved-vault" \
  --approved-ref proposal \
  --platform feishu \
  --user-id ou/admin \
  --identity-key feishu:user:admin \
  --actor-user admin-user >/dev/null 2>&1; then
  fail "knowledge helper allowed named proposal ref as approved source"
else
  ok "knowledge helper rejects named proposal ref as approved source"
fi

proposal_sha="$(git -C "$knowledge_seed" rev-parse proposal)"
if bash "$ROOT/bin/knot-knowledge.sh" sync-approved \
  --root "$knowledge_root" \
  --repo-url "$knowledge_remote" \
  --mirror "$knowledge_root/workspace/knowledge/unapproved-sha-vault" \
  --approved-ref "$proposal_sha" \
  --platform feishu \
  --user-id ou/admin \
  --identity-key feishu:user:admin \
  --actor-user admin-user >/dev/null 2>&1; then
  fail "knowledge helper allowed proposal commit SHA as approved source"
else
  ok "knowledge helper rejects proposal commit SHA outside main history"
fi

if bash "$ROOT/bin/knot-knowledge.sh" admin-review \
  --root "$knowledge_root" \
  --mirror "$knowledge_root/workspace/knowledge/vault" \
  --platform feishu \
  --user-id ou/member \
  --identity-key feishu:user:member \
  --actor-user member-user >/dev/null 2>&1; then
  fail "knowledge helper allowed member admin review"
else
  ok "knowledge helper rejects member admin review"
fi

mkdir -p "$knowledge_root/workspace/knowledge/vault/.github/workflows" \
  "$knowledge_root/workspace/knowledge/vault/.skills/knot-workflow" \
  "$knowledge_root/workspace/knowledge/vault/components/knot-skills" \
  "$knowledge_root/workspace/knowledge/vault/docs/schemas" \
  "$knowledge_root/workspace/knowledge/vault/bin" \
  "$knowledge_root/workspace/knowledge/vault/lib/knot" \
  "$knowledge_root/workspace/knowledge/vault/.skills/knot-setup/references"
printf '%s\n' 'name: unsafe' > "$knowledge_root/workspace/knowledge/vault/.github/workflows/unsafe.yml"
printf '%s\n' 'skill change' > "$knowledge_root/workspace/knowledge/vault/.skills/knot-workflow/SKILL.md"
printf '%s\n' 'component skill change' > "$knowledge_root/workspace/knowledge/vault/components/knot-skills/SKILL.md"
printf '%s\n' '{}' > "$knowledge_root/workspace/knowledge/vault/docs/schemas/example.schema.json"
printf '%s\n' '# helper' > "$knowledge_root/workspace/knowledge/vault/bin/knot-helper.sh"
printf '%s\n' '# library' > "$knowledge_root/workspace/knowledge/vault/lib/knot/example.sh"
printf '%s\n' '| User | Workspace |' > "$knowledge_root/workspace/knowledge/vault/.skills/knot-setup/references/permissions.template.md"
if review_output="$(bash "$ROOT/bin/knot-knowledge.sh" admin-review \
  --root "$knowledge_root" \
  --mirror "$knowledge_root/workspace/knowledge/vault" \
  --platform feishu \
  --user-id ou/admin \
  --identity-key feishu:user:admin \
  --actor-user admin-user 2>&1)" &&
  printf '%s\n' "$review_output" | grep -Fq "high_risk=true" &&
  printf '%s\n' "$review_output" | grep -Fq ".github/workflows/unsafe.yml" &&
  printf '%s\n' "$review_output" | grep -Fq ".skills/knot-workflow/SKILL.md" &&
  printf '%s\n' "$review_output" | grep -Fq "components/knot-skills/SKILL.md" &&
  printf '%s\n' "$review_output" | grep -Fq "docs/schemas/example.schema.json" &&
  printf '%s\n' "$review_output" | grep -Fq "bin/knot-helper.sh" &&
  printf '%s\n' "$review_output" | grep -Fq "lib/knot/example.sh" &&
  printf '%s\n' "$review_output" | grep -Fq ".skills/knot-setup/references/permissions.template.md"; then
  ok "knowledge helper flags protected workflow, skill, schema, helper, and permission changes for admin review"
else
  fail "knowledge helper did not flag high-risk protected changes: $review_output"
fi

printf '%s\n' 'draft knowledge' > "$knowledge_root/workspace/users/member-user/work/proposal/draft.md"
if proposal_output="$(bash "$ROOT/bin/knot-knowledge.sh" propose \
  --root "$knowledge_root" \
  --source "$knowledge_root/workspace/users/member-user/work/proposal" \
  --title "draft-note" \
  --platform feishu \
  --user-id ou/member \
  --identity-key feishu:user:member \
  --actor-user member-user 2>&1)" &&
  proposal_path="$(printf '%s\n' "$proposal_output" | sed -n 's/^proposal: //p')" &&
  [ -f "$proposal_path/manifest.tsv" ] &&
  [ -f "$proposal_path/files/draft.md" ]; then
  ok "knowledge helper lets members create scoped patch-bundle proposals"
else
  fail "knowledge helper did not create member proposal bundle: ${proposal_output:-}"
fi

if GH_TOKEN=admin-token bash "$ROOT/bin/knot-knowledge.sh" propose \
  --root "$knowledge_root" \
  --source "$knowledge_root/workspace/users/member-user/work/proposal" \
  --title "credential-leak" \
  --platform feishu \
  --user-id ou/member \
  --identity-key feishu:user:member \
  --actor-user member-user >/dev/null 2>&1; then
  fail "knowledge helper allowed member proposal with GitHub token in environment"
else
  ok "knowledge helper rejects member proposal when GitHub token is visible"
fi

if bash "$ROOT/bin/knot-knowledge.sh" propose \
  --root "$knowledge_root" \
  --source "$knowledge_root/workspace/knowledge/vault" \
  --title "mirror-source" \
  --platform feishu \
  --user-id ou/member \
  --identity-key feishu:user:member \
  --actor-user member-user >/dev/null 2>&1; then
  fail "knowledge helper allowed member proposal from approved mirror"
else
  ok "knowledge helper rejects member proposal from approved mirror"
fi
