#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAILURES=0
TMP_PARENT=""
UNSAFE_ROOT=""

usage() {
  cat <<'EOF'
Usage: bash tests/integration.sh [--root DIR]

Runs Knot helper smoke tests against temporary workspaces.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      if [ "$#" -eq 0 ]; then
        printf 'MISS --root requires a value\n'
        exit 1
      fi
      ROOT="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'MISS unknown argument: %s\n' "$1"
      exit 1
      ;;
  esac
  shift
done

ROOT="$(cd "$ROOT" && pwd)" || {
  printf 'MISS root directory does not exist: %s\n' "$ROOT"
  exit 1
}
# shellcheck source=bootstrap/lib.sh
. "$ROOT/bootstrap/lib.sh"

ok() { printf 'OK   %s\n' "$1"; }
fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

cleanup() {
  [ -z "$TMP_PARENT" ] || rm -rf "$TMP_PARENT"
  [ -z "$UNSAFE_ROOT" ] || rm -rf "$UNSAFE_ROOT"
}
trap cleanup EXIT

TMP_PARENT="$(mktemp -d)"
tmp_root="$TMP_PARENT/root with spaces"
mkdir -p "$tmp_root"

workspace_exports="$(bash "$ROOT/bootstrap/knot-workspace.sh" \
  --root "$tmp_root" \
  --platform feishu \
  --chat-id "oc/test group" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --group-slug "example-group" \
  --identity-key "feishu:user:ou-test" \
  --name "Smoke Test" \
  --group-name "Example Group")" || {
  fail "knot-workspace smoke test failed"
  exit 1
}

if eval "$workspace_exports" &&
  [ "$KNOT_ACTIVE_WORKSPACE" = "$tmp_root/workspace/users/example-user" ] &&
  [ "$KNOT_USER_WORKSPACE" = "$tmp_root/workspace/users/example-user" ] &&
  [ "$KNOT_GROUP_WORKSPACE" = "$tmp_root/workspace/groups/example-group" ] &&
  [ -n "$KNOT_CONVERSATION_DIR" ]; then
  ok "knot-workspace prints source-safe exports for paths with spaces"
else
  fail "knot-workspace exports did not resolve expected user/group paths"
fi

user_workspace="$tmp_root/workspace/users/example-user"
group_workspace="$tmp_root/workspace/groups/example-group"
conversation_dir="$KNOT_CONVERSATION_DIR"

if [ -d "$user_workspace/deliverables" ] &&
  [ -d "$group_workspace/deliverables" ] &&
  [ -f "$conversation_dir/metadata.tsv" ] &&
  grep -Fq $'actor_user\texample-user' "$conversation_dir/metadata.tsv"; then
  ok "knot-workspace creates user/group workspaces and conversation metadata"
else
  fail "knot-workspace did not create expected user/group/conversation state"
fi

mkdir -p "$tmp_root/workspace/admin"
cat > "$tmp_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Example User | example-user | feishu | ou/test user | example-group | oc/test group | feishu:user:ou-test | Smoke Test | member | session | smoke |
| Jane Example | jane-example | feishu | ou/jane | product-room | oc/product | feishu:user:ou/jane | Jane Example | member | session | smoke |
EOF

if resolved_exports="$(bash "$ROOT/bootstrap/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/jane" --identity-key "feishu:user:ou/jane" --name "Ignored Name" --group-name "Ignored Group")" &&
  eval "$resolved_exports" &&
  [ "$KNOT_ACTIVE_WORKSPACE" = "$tmp_root/workspace/users/jane-example" ] &&
  [ "$KNOT_GROUP_WORKSPACE" = "$tmp_root/workspace/groups/product-room" ]; then
  ok "knot-workspace resolves user/group slugs from permissions table"
else
  fail "knot-workspace did not resolve permissions table slugs"
fi

if resolved_exports="$(bash "$ROOT/bootstrap/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/bob" --identity-key "feishu:user:ou/bob" --name "Bob Example" --group-name "Ignored Group")" &&
  eval "$resolved_exports" &&
  [ -z "$KNOT_GROUP_WORKSPACE" ]; then
  ok "knot-workspace requires actor match before exposing permissions group"
else
  fail "knot-workspace exposed permissions group to unmatched actor"
fi

if resolved_exports="$(bash "$ROOT/bootstrap/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/jane" --identity-key "feishu:user:wrong" --name "Jane Example" --group-name "Ignored Group")" &&
  eval "$resolved_exports" &&
  [ "$KNOT_ACTIVE_WORKSPACE" != "$tmp_root/workspace/users/jane-example" ] &&
  [ -z "$KNOT_GROUP_WORKSPACE" ]; then
  ok "knot-workspace rejects mismatched explicit identity key before permission fallback"
else
  fail "knot-workspace resolved permissions row with mismatched explicit identity key"
fi

if bash "$ROOT/bootstrap/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id $'oc/bad\tchat' --user-id "ou/test user" --user-slug "bad-meta" >/dev/null 2>&1; then
  fail "knot-workspace allowed tab in chat metadata"
else
  ok "knot-workspace rejects tabs in chat metadata"
fi

printf 'ok\n' > "$user_workspace/deliverables/result.txt"
if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/result.txt" >/dev/null; then
  ok "knot-attachment allows current user deliverable"
else
  fail "knot-attachment rejected current user deliverable"
fi

printf 'group\n' > "$group_workspace/deliverables/group.txt"
if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$group_workspace/deliverables/group.txt" >/dev/null; then
  ok "knot-attachment allows current group deliverable"
else
  fail "knot-attachment rejected current group deliverable"
fi

mkdir -p "$tmp_root/generated"
printf 'generated\n' > "$tmp_root/generated/image.png"
if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$tmp_root/generated/image.png")"; then
  expected_deliverable="$(resolve_path "$user_workspace/deliverables/image.png")"
  if [ -f "$user_workspace/deliverables/image.png" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq '```cc-connect-attachments' &&
    printf '%s\n' "$deliver_output" | grep -Fq "image: $expected_deliverable"; then
    ok "knot-deliver copies generated artifact to user deliverables"
  else
    fail "knot-deliver did not copy generated artifact to user deliverables"
  fi
else
  fail "knot-deliver rejected generated artifact"
fi

if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$tmp_root/generated/image.png" --target group --output-name "shared.png")"; then
  if [ -f "$group_workspace/deliverables/shared.png" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/shared.png")"; then
    ok "knot-deliver can target current group deliverables explicitly"
  else
    fail "knot-deliver did not copy generated artifact to group deliverables"
  fi
else
  fail "knot-deliver rejected explicit group delivery"
fi

printf 'env-generated\n' > "$tmp_root/generated/env.png"
if deliver_output="$(env \
  KNOT_ROOT="$tmp_root" \
  KNOT_PLATFORM=feishu \
  KNOT_PLATFORM_USER_ID="ou/test user" \
  KNOT_ACTOR_USER=example-user \
  KNOT_SOURCE_GROUP=example-group \
  KNOT_CHAT_ID="oc/test group" \
  KNOT_IDENTITY_KEY="feishu:user:ou-test" \
  bash "$ROOT/bootstrap/knot-deliver.sh" --kind image --path "$tmp_root/generated/env.png" --target group --output-name "env-shared.png")"; then
  if [ -f "$group_workspace/deliverables/env-shared.png" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/env-shared.png")"; then
    ok "knot-deliver reads current context from KNOT_* environment"
  else
    fail "knot-deliver env-context delivery did not create expected group deliverable"
  fi
else
  fail "knot-deliver did not accept KNOT_* environment context"
fi

if attach_output="$(env \
  KNOT_ROOT="$tmp_root" \
  KNOT_PLATFORM=feishu \
  KNOT_PLATFORM_USER_ID="ou/test user" \
  KNOT_ACTOR_USER=example-user \
  KNOT_SOURCE_GROUP=example-group \
  KNOT_CHAT_ID="oc/test group" \
  KNOT_IDENTITY_KEY="feishu:user:ou-test" \
  bash "$ROOT/bootstrap/knot-attachment.sh" --kind image --path "$group_workspace/deliverables/env-shared.png")" &&
  printf '%s\n' "$attach_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/env-shared.png")"; then
  ok "knot-attachment reads current context from KNOT_* environment"
else
  fail "knot-attachment did not accept KNOT_* environment context"
fi

if unauthorized_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "unauthorized-group" --kind image --path "$tmp_root/generated/image.png" --target group 2>&1)"; then
  fail "knot-deliver allowed unauthorized explicit group delivery"
elif printf '%s\n' "$unauthorized_output" | grep -Fq "not authorized"; then
  ok "knot-deliver rejects unauthorized explicit group delivery"
else
  fail "knot-deliver unauthorized group rejection had wrong error: $unauthorized_output"
fi

if unauthorized_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --identity-key "feishu:user:wrong" --kind image --path "$tmp_root/generated/image.png" --target group 2>&1)"; then
  fail "knot-deliver allowed group delivery with mismatched identity key"
elif printf '%s\n' "$unauthorized_output" | grep -Fq "not authorized"; then
  ok "knot-deliver rejects mismatched identity key for group delivery"
else
  fail "knot-deliver identity mismatch rejection had wrong error: $unauthorized_output"
fi

if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/result.txt" --target group --output-name "result-shared.txt")"; then
  if [ -f "$group_workspace/deliverables/result-shared.txt" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq "file: $(resolve_path "$group_workspace/deliverables/result-shared.txt")"; then
    ok "knot-deliver copies user deliverable into group deliverables when target is group"
  else
    fail "knot-deliver did not copy user deliverable into group deliverables"
  fi
else
  fail "knot-deliver rejected user deliverable targeted to group"
fi

ln -s "$tmp_root/escaped-delivery.png" "$user_workspace/deliverables/symlink.png"
if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$tmp_root/generated/image.png" --output-name "symlink.png")"; then
  if [ ! -e "$tmp_root/escaped-delivery.png" ] &&
    [ -f "$user_workspace/deliverables/symlink-1.png" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$user_workspace/deliverables/symlink-1.png")"; then
    ok "knot-deliver avoids writing through deliverables symlinks"
  else
    fail "knot-deliver wrote through or failed to avoid deliverables symlink"
  fi
else
  fail "knot-deliver rejected delivery when output name collided with symlink"
fi

other_user_workspace="$tmp_root/workspace/users/other-user"
mkdir -p "$other_user_workspace/deliverables"
printf 'private\n' > "$other_user_workspace/deliverables/private.txt"
if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_user_workspace/deliverables/private.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed artifact from another user workspace"
else
  ok "knot-deliver rejects artifact from another user workspace"
fi

other_group_workspace="$tmp_root/workspace/groups/other-group"
mkdir -p "$other_group_workspace/deliverables"
printf 'group-private\n' > "$other_group_workspace/deliverables/private.txt"
if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_group_workspace/deliverables/private.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed artifact from another group workspace"
else
  ok "knot-deliver rejects artifact from another group workspace"
fi

printf 'audit\n' > "$conversation_dir/audit.txt"
if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$conversation_dir/audit.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed artifact from conversations metadata"
else
  ok "knot-deliver rejects artifact from conversations metadata"
fi
if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$conversation_dir/audit.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed artifact from conversations metadata"
else
  ok "knot-attachment rejects artifact from conversations metadata"
fi

printf 'external\n' > "$tmp_root/generated/external.txt"
ln -s "$tmp_root/generated/external.txt" "$other_user_workspace/deliverables/external-link.txt"
if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_user_workspace/deliverables/external-link.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed symlink path from another user workspace"
else
  ok "knot-deliver rejects symlink path from another user workspace"
fi

printf 'outside\n' > "$tmp_root/outside.txt"
if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$tmp_root/outside.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed file outside current user/group workspaces"
else
  ok "knot-attachment rejects file outside current user/group workspaces"
fi

ln -s "$tmp_root/outside.txt" "$user_workspace/deliverables/leak.txt"
if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/leak.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed symlink escaping current user workspace"
else
  ok "knot-attachment rejects symlink escaping current user workspace"
fi

mv "$user_workspace/deliverables" "$user_workspace/deliverables-real"
ln -s "$user_workspace/deliverables-real" "$user_workspace/deliverables"
if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables-real/result.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed symlinked user deliverables directory"
else
  ok "knot-attachment rejects symlinked user deliverables directory"
fi
rm "$user_workspace/deliverables"
mv "$user_workspace/deliverables-real" "$user_workspace/deliverables"

ln -s "$user_workspace" "$tmp_root/workspace/users/alias-user"
if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "alias-user" --kind file --path "$user_workspace/deliverables/result.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed symlinked user workspace slug"
else
  ok "knot-attachment rejects symlinked user workspace slug"
fi
if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "alias-user" --kind file --path "$tmp_root/generated/external.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed symlinked user workspace slug"
else
  ok "knot-deliver rejects symlinked user workspace slug"
fi

ln -s "$group_workspace" "$tmp_root/workspace/groups/alias-group"
if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "alias-group" --target group --kind file --path "$tmp_root/generated/external.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed symlinked group workspace slug"
else
  ok "knot-deliver rejects symlinked group workspace slug"
fi

UNSAFE_ROOT="$(mktemp -d)"
git -C "$UNSAFE_ROOT" init >/dev/null 2>&1
git -C "$UNSAFE_ROOT" remote add backup https://github.com/realraelrr/knot-agent.git
if bash "$ROOT/bootstrap/knot-backup.sh" --root "$UNSAFE_ROOT" >/dev/null 2>&1; then
  fail "knot-backup allowed scaffold backup remote"
else
  ok "knot-backup rejects scaffold backup remote"
fi

runtime_root="$TMP_PARENT/runtime-root"
mkdir -p "$runtime_root/runtime/weixin/bin"
printf '#!/usr/bin/env bash\n' > "$runtime_root/runtime/weixin/bin/cc-connect"
printf '#!/usr/bin/env bash\n' > "$runtime_root/runtime/weixin/run-weixin.sh"
chmod +x "$runtime_root/runtime/weixin/bin/cc-connect" "$runtime_root/runtime/weixin/run-weixin.sh"
cat > "$runtime_root/runtime/weixin/config.weixin.toml" <<'EOF'
[[projects]]
name = "knot"

[projects.knot_workspace]
enabled = true
helper = "${KNOT_ROOT}/bootstrap/knot-workspace.sh"
root = "${KNOT_ROOT}"

[[projects.platforms]]
type = "weixin"
EOF
cat > "$runtime_root/runtime/weixin/.env" <<EOF
KNOT_ROOT=$runtime_root
WEIXIN_ALLOW_FROM=*
KNOT_ACTIVE_WORKSPACE=$runtime_root/workspace/users/stale
EOF
if bash "$ROOT/bootstrap/knot-runtime-check.sh" --root "$runtime_root" --platform weixin >/dev/null 2>&1; then
  fail "knot-runtime-check allowed static KNOT_ACTIVE_WORKSPACE in .env"
else
  ok "knot-runtime-check rejects static KNOT_ACTIVE_WORKSPACE in .env"
fi

install_root="$TMP_PARENT/install-root"
mkdir -p "$install_root/.skills/knot-setup" "$install_root/.skills/knot-workflow"
cp -R "$ROOT/bootstrap" "$install_root/bootstrap"
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
if CODEX_HOME="$install_root/codex-home" bash "$install_root/bootstrap/knot-install.sh" \
  --root "$install_root" \
  --skip-components \
  --skip-build \
  --skip-backup-remote \
  --skip-doctor >/dev/null; then
  if [ -d "$install_root/workspace/users" ] &&
    [ -d "$install_root/runtime" ] &&
    [ -f "$install_root/workspace/admin/permissions.md" ] &&
    [ -f "$install_root/codex-home/AGENTS.md" ] &&
    [ -x "$install_root/bootstrap/knot-workspace.sh" ] &&
    [ -f "$install_root/bootstrap/component-lock.sh" ] &&
    [ ! -x "$install_root/bootstrap/component-lock.sh" ] &&
    [ "$(readlink "$install_root/codex-home/skills/planning-with-files")" = "$install_root/components/planning-with-files/.codex/skills/planning-with-files" ] &&
    [ "$(readlink "$install_root/codex-home/skills/docling-skill")" = "$install_root/components/docling-skill/.codex/skills/docling-skill" ] &&
    [ "$(readlink "$install_root/codex-home/skills/md-for-human")" = "$install_root/components/md-for-human/.codex/skills/md-for-human" ] &&
    [ "$(readlink "$install_root/codex-home/skills/handoff")" = "$install_root/components/handoff-skill/.codex/skills/handoff" ] &&
    [ ! -x "$install_root/bootstrap/lib.sh" ]; then
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
cp -R "$ROOT/bootstrap" "$repair_root/bootstrap"
cp -R "$ROOT/.skills/knot-setup/references" "$repair_root/.skills/knot-setup/references"
cp "$ROOT/AGENTS.md" "$repair_root/AGENTS.md"
cp "$ROOT/components.lock" "$repair_root/components.lock"
cp "$ROOT/.gitignore" "$repair_root/.gitignore"
printf '%s\n' 'name: knot-workflow' > "$repair_root/.skills/knot-workflow/SKILL.md"
printf '%s\n' 'custom global instructions' > "$repair_root/codex-home/AGENTS.md"
printf '%s\n' 'custom permissions' > "$repair_root/workspace/admin/permissions.md"
printf '%s\n' 'custom feedback' > "$repair_root/workspace/admin/knowledge-feedback.md"
printf '%s\n' 'custom backup policy' > "$repair_root/workspace/admin/backup-policy.md"

if CODEX_HOME="$repair_root/codex-home" bash "$repair_root/bootstrap/knot-install.sh" \
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
if CODEX_HOME="$repair_root/codex-home" bash "$repair_root/bootstrap/knot-install.sh" \
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

  if output="$(CODEX_HOME="$lock_root/codex-home" bash "$lock_root/bootstrap/knot-install.sh" \
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
      . "$ROOT/bootstrap/doctor/common.sh"
      . "$ROOT/bootstrap/component-lock.sh"
      . "$ROOT/bootstrap/doctor/source.sh"
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

  if output="$(CODEX_HOME="$lock_root/codex-home" bash "$lock_root/bootstrap/knot-install.sh" \
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
      . "$ROOT/bootstrap/doctor/common.sh"
      . "$ROOT/bootstrap/doctor/source.sh"
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
      . "$ROOT/bootstrap/doctor/common.sh"
      . "$ROOT/bootstrap/doctor/installed.sh"
      run_workspace_contract_checks
      [ "$FAILURES" -eq 0 ]
    '
}

doc_root="$TMP_PARENT/doc-contract-root"
mkdir -p \
  "$doc_root/bootstrap/doctor" \
  "$doc_root/.skills/knot-setup/references" \
  "$doc_root/.skills/knot-workflow" \
  "$doc_root/docs" \
  "$doc_root/workspace/admin"
cp "$ROOT/bootstrap/doctor/common.sh" "$doc_root/bootstrap/doctor/common.sh"
cp "$ROOT/bootstrap/doctor/source.sh" "$doc_root/bootstrap/doctor/source.sh"
cp "$ROOT/bootstrap/doctor/installed.sh" "$doc_root/bootstrap/doctor/installed.sh"
cp "$ROOT/AGENTS.md" "$doc_root/AGENTS.md"
cp "$ROOT/.skills/knot-workflow/SKILL.md" "$doc_root/.skills/knot-workflow/SKILL.md"
cp "$ROOT/.skills/knot-setup/references/"*.md "$doc_root/.skills/knot-setup/references/"
cp "$ROOT/docs/im-smoke-sop.md" "$doc_root/docs/im-smoke-sop.md"
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

if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
