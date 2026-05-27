# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

mode_of() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

style_denied_count() {
  local conversation_dir="$1"
  local event="$2"
  local reason="$3"

  jq -s --arg event "$event" --arg reason "$reason" \
    '[.[] | select(.event == $event and .reason_code == $reason)] | length' \
    "$conversation_dir/events.jsonl"
}

style_root="$TMP_PARENT/working-style-root"
mkdir -p "$style_root/workspace/admin"
cat > "$style_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Direct User | direct-user | feishu | ou/direct-user |  | oc/direct-style | feishu:user:direct | Direct User | member | session | smoke |
| Direct User | direct-user | feishu | ou/direct-user | style-group | oc/group-style | feishu:user:direct | Direct User | member | session | smoke |
EOF

style_workspace_exports="$(bash "$ROOT/bin/knot-workspace.sh" \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --user-slug "direct-user" \
  --identity-key "feishu:user:direct" \
  --emit-conversation-initialized)" || {
  fail "knot-workspace setup for working style tests failed"
  exit 1
}
eval "$style_workspace_exports"

style_user_workspace="$KNOT_USER_WORKSPACE"
style_conversation_dir="$KNOT_CONVERSATION_DIR"
style_file="$style_user_workspace/style.md"
style_pack_file="$style_user_workspace/.knot/style-pack.md"
style_patch_file="$style_user_workspace/.knot/style.patch"
style_target_rel="workspace/users/direct-user/style.md"

cat > "$style_file" <<'EOF'
---
version: 1
updated: 2026-01-01
reviewed: 2026-01-01
---
# Working Style

## Communication
- Prefers concise status updates with concrete verification evidence.
EOF

pack_working_style() {
  bash "$ROOT/bin/knot-working-style-pack.sh" pack \
    --root "$style_root" \
    --platform feishu \
    --chat-id "oc/direct-style" \
    --user-id "ou/direct-user" \
    --identity-key "feishu:user:direct" \
    --actor-user direct-user \
    --scope direct \
    --active-workspace "$style_user_workspace" \
    --user-workspace "$style_user_workspace" \
    --actor-workspace "$style_user_workspace" \
    --conversation-dir "$style_conversation_dir"
}

apply_working_style_patch() {
  bash "$ROOT/bin/knot-working-style-apply.sh" apply \
    --root "$style_root" \
    --patch "$style_patch_file" \
    --platform feishu \
    --chat-id "oc/direct-style" \
    --user-id "ou/direct-user" \
    --identity-key "feishu:user:direct" \
    --actor-user direct-user \
    --scope direct \
    --active-workspace "$style_user_workspace" \
    --user-workspace "$style_user_workspace" \
    --actor-workspace "$style_user_workspace" \
    --conversation-dir "$style_conversation_dir"
}

write_style_patch() {
  local target="$1"
  local base_sha256="$2"
  local patch_file="${3:-$style_patch_file}"

  {
    printf 'target: %s\n' "$target"
    printf 'base_sha256: %s\n\n' "$base_sha256"
    cat
  } > "$patch_file"
}

assert_style_patch_denied_unchanged() {
  local label="$1"
  local expected_reason="$2"
  local before_hash
  local before_events
  local after_events

  before_hash="$(file_sha256 "$style_file")"
  before_events="$(style_denied_count "$style_conversation_dir" working_style.patch.denied "$expected_reason")"
  if apply_working_style_patch >/dev/null 2>&1; then
    fail "$label"
    return
  fi
  after_events="$(style_denied_count "$style_conversation_dir" working_style.patch.denied "$expected_reason")"
  if [ "$(file_sha256 "$style_file")" = "$before_hash" ] &&
    [ "$after_events" -gt "$before_events" ]; then
    ok "$label"
  else
    fail "$label"
  fi
}

if style_pack_path="$(pack_working_style)" &&
  [ "$(absolute_path "$style_pack_path")" = "$(absolute_path "$style_pack_file")" ] &&
  [ -f "$style_pack_file" ] &&
  grep -Fq "Knot Working Style Pack" "$style_pack_file" &&
  grep -Fq "actor_user: direct-user" "$style_pack_file" &&
  grep -Fq "write_target: workspace/users/direct-user/style.md" "$style_pack_file" &&
  grep -Fq "Prefers concise status updates" "$style_pack_file" &&
  [ "$(mode_of "$style_pack_file")" = "600" ] &&
  [ "$(mode_of "$style_file")" = "600" ] &&
  [ ! -e "$style_user_workspace/memory/active.md" ] &&
  [ ! -e "$style_user_workspace/memory/followups.md" ]; then
  ok "working style pack creates only owner-only working style context"
else
  fail "working style pack did not create expected bounded context"
fi

if [ -f "$style_pack_file" ]; then
  first_pack_hash="$(file_sha256 "$style_pack_file")"
  if second_pack_path="$(pack_working_style)" &&
    [ "$(absolute_path "$second_pack_path")" = "$(absolute_path "$style_pack_file")" ] &&
    [ "$(file_sha256 "$style_pack_file")" = "$first_pack_hash" ]; then
    ok "working style pack output is deterministic for unchanged inputs"
  else
    fail "working style pack output changed for unchanged inputs"
  fi
else
  fail "working style pack output is deterministic for unchanged inputs"
fi

if jq -e 'select(.event == "working_style.pack.generated" and .status == "recorded")' "$style_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style pack records compact audit event"
else
  fail "working style pack did not record compact audit event"
fi

group_style_exports="$(bash "$ROOT/bin/knot-workspace.sh" \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/group-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --emit-conversation-initialized)" || {
  fail "knot-workspace setup for group working style tests failed"
  exit 1
}
eval "$group_style_exports"
group_style_active_workspace="$KNOT_ACTIVE_WORKSPACE"
group_style_actor_workspace="${KNOT_ACTOR_WORKSPACE:-}"
group_style_user_workspace="$KNOT_USER_WORKSPACE"
group_style_conversation_dir="$KNOT_CONVERSATION_DIR"
group_style_pack_file="$group_style_actor_workspace/.knot/style-pack.md"
group_style_patch_file="$group_style_actor_workspace/.knot/style.patch"

if group_style_pack_path="$(bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/group-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug style-group \
  --active-workspace "$group_style_active_workspace" \
  --user-workspace "$group_style_user_workspace" \
  --actor-workspace "$group_style_actor_workspace" \
  --conversation-dir "$group_style_conversation_dir")" &&
  [ "$(absolute_path "$group_style_pack_path")" = "$(absolute_path "$group_style_pack_file")" ] &&
  [ -f "$group_style_pack_file" ] &&
  grep -Fq "scope: working_style" "$group_style_pack_file" &&
  grep -Fq "mode: read_only" "$group_style_pack_file" &&
  grep -Fq "active_workspace: workspace/groups/style-group" "$group_style_pack_file" &&
  grep -Fq "actor_workspace: workspace/groups/style-group/work/direct-user" "$group_style_pack_file" &&
  grep -Fq "source_style: workspace/users/direct-user/style.md" "$group_style_pack_file" &&
  grep -Fq "Prefers concise status updates" "$group_style_pack_file" &&
  [ "$(mode_of "$group_style_pack_file")" = "600" ]; then
  ok "working style group scope writes read-only pack to actor lane"
else
  fail "working style group scope did not write expected read-only pack"
fi

group_style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$group_style_base" "$group_style_patch_file" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,1 +9,2 @@
 - Prefers concise status updates with concrete verification evidence.
+- group chat must not silently write style changes.
EOF
before_group_apply_hash="$(file_sha256 "$style_file")"
before_group_apply_denials="$(style_denied_count "$group_style_conversation_dir" working_style.patch.denied working_style_workspace_mismatch)"
if bash "$ROOT/bin/knot-working-style-apply.sh" apply \
  --root "$style_root" \
  --patch "$group_style_patch_file" \
  --platform feishu \
  --chat-id "oc/group-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug style-group \
  --active-workspace "$group_style_active_workspace" \
  --user-workspace "$group_style_user_workspace" \
  --actor-workspace "$group_style_actor_workspace" \
  --conversation-dir "$group_style_conversation_dir" >/dev/null 2>&1; then
  fail "working style apply allowed group scope mutation"
elif [ "$(file_sha256 "$style_file")" = "$before_group_apply_hash" ] &&
  [ "$(style_denied_count "$group_style_conversation_dir" working_style.patch.denied working_style_workspace_mismatch)" -gt "$before_group_apply_denials" ]; then
  ok "working style apply rejects group scope mutation"
else
  fail "working style group scope apply did not preserve target and audit"
fi

before_implicit_group_pack_denials="$(style_denied_count "$style_conversation_dir" working_style.pack.denied working_style_workspace_mismatch)"
if env KNOT_SCOPE= bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug style-group \
  --active-workspace "$style_user_workspace" \
  --user-workspace "$style_user_workspace" \
  --conversation-dir "$style_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack inferred direct scope despite group slug"
elif [ "$(style_denied_count "$style_conversation_dir" working_style.pack.denied working_style_workspace_mismatch)" -gt "$before_implicit_group_pack_denials" ]; then
  ok "working style pack rejects missing scope with group slug"
else
  fail "working style pack missing-scope group slug denial was not audited"
fi

before_direct_group_pack_denials="$(style_denied_count "$style_conversation_dir" working_style.pack.denied working_style_workspace_mismatch)"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug style-group \
  --scope direct \
  --active-workspace "$style_user_workspace" \
  --user-workspace "$style_user_workspace" \
  --conversation-dir "$style_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack allowed direct scope with group slug"
elif [ "$(style_denied_count "$style_conversation_dir" working_style.pack.denied working_style_workspace_mismatch)" -gt "$before_direct_group_pack_denials" ]; then
  ok "working style pack rejects direct scope with group slug"
else
  fail "working style pack direct-scope group slug denial was not audited"
fi

implicit_group_apply_backup="$style_user_workspace/.implicit-group-apply.backup"
cp "$style_file" "$implicit_group_apply_backup"
implicit_group_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$implicit_group_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,1 +9,2 @@
 - Prefers concise status updates with concrete verification evidence.
+- implicit group scope must not write style changes.
EOF
before_implicit_group_apply_denials="$(style_denied_count "$style_conversation_dir" working_style.patch.denied working_style_workspace_mismatch)"
if env KNOT_SCOPE= bash "$ROOT/bin/knot-working-style-apply.sh" apply \
  --root "$style_root" \
  --patch "$style_patch_file" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug style-group \
  --active-workspace "$style_user_workspace" \
  --user-workspace "$style_user_workspace" \
  --conversation-dir "$style_conversation_dir" >/dev/null 2>&1; then
  fail "working style apply inferred direct scope despite group slug"
  mv "$implicit_group_apply_backup" "$style_file"
  chmod 600 "$style_file"
elif [ "$(file_sha256 "$style_file")" = "$implicit_group_base" ] &&
  [ "$(style_denied_count "$style_conversation_dir" working_style.patch.denied working_style_workspace_mismatch)" -gt "$before_implicit_group_apply_denials" ]; then
  ok "working style apply rejects missing scope with group slug"
  rm -f "$implicit_group_apply_backup"
else
  fail "working style apply missing-scope group slug denial did not preserve target and audit"
  mv "$implicit_group_apply_backup" "$style_file"
  chmod 600 "$style_file"
fi
eval "$style_workspace_exports"

assert_style_pack_denied_existing_content() {
  local label="$1"
  local content="$2"
  local style_backup="$style_user_workspace/.style.backup"
  local pack_backup="$style_user_workspace/.knot/.pack.backup"
  local before_events
  local after_events
  local before_pack_hash

  cp "$style_file" "$style_backup"
  cp "$style_pack_file" "$pack_backup"
  printf '%s' "$content" > "$style_file"
  chmod 600 "$style_file"
  before_pack_hash="$(file_sha256 "$style_pack_file")"
  before_events="$(style_denied_count "$style_conversation_dir" working_style.pack.denied working_style_content_denied)"

  if pack_working_style >/dev/null 2>&1; then
    fail "$label"
  else
    after_events="$(style_denied_count "$style_conversation_dir" working_style.pack.denied working_style_content_denied)"
    if [ "$(file_sha256 "$style_pack_file")" = "$before_pack_hash" ] &&
      [ "$after_events" -gt "$before_events" ]; then
      ok "$label"
    else
      fail "$label"
    fi
  fi

  mv "$style_backup" "$style_file"
  mv "$pack_backup" "$style_pack_file"
  chmod 600 "$style_file" "$style_pack_file"
}

assert_style_pack_denied_existing_content \
  "working style pack rejects existing transcript blocks" \
  $'# Working Style\n\n```transcript\nUser: copied raw chat\n'
assert_style_pack_denied_existing_content \
  "working style pack rejects existing secrets-looking content" \
  $'# Working Style\n\nAPI_KEY=secret-value\n'
assert_style_pack_denied_existing_content \
  "working style pack rejects existing bullet secrets-looking content" \
  $'# Working Style\n\n- password: hunter2\n'
long_existing_style="$(printf 'x%.0s' $(seq 1 1700))"
assert_style_pack_denied_existing_content \
  "working style pack rejects existing oversized content" \
  "# Working Style

$long_existing_style
"

if env -u KNOT_CONVERSATION_DIR bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$style_user_workspace" \
  --user-workspace "$style_user_workspace" >/dev/null 2>&1; then
  fail "working style pack allowed generation without conversation audit target"
else
  ok "working style pack requires conversation audit target"
fi

invalid_audit_dir="$style_root/workspace/conversations/feishu/not_chat"
mkdir -p "$invalid_audit_dir"
before_pack_hash="$(file_sha256 "$style_pack_file")"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$style_user_workspace" \
  --user-workspace "$style_user_workspace" \
  --conversation-dir "$invalid_audit_dir" >/dev/null 2>&1; then
  fail "working style pack allowed generation without a valid audit event"
elif [ "$(file_sha256 "$style_pack_file")" = "$before_pack_hash" ] &&
  [ ! -e "$invalid_audit_dir/events.jsonl" ]; then
  ok "working style pack fails closed when audit event cannot be recorded"
else
  fail "working style pack changed runtime pack after audit failure"
fi

denied_hash="$(sha256_hex_pair feishu "oc/style-denied")"
denied_conversation_dir="$style_root/workspace/conversations/feishu/chat_${denied_hash:0:24}"
mkdir -p "$denied_conversation_dir"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$style_root" \
  --platform feishu \
  --chat-id "oc/style-denied" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$style_root/workspace/users/other-user" \
  --user-workspace "$style_user_workspace" \
  --conversation-dir "$denied_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack allowed mismatched active/user workspace"
else
  ok "working style pack fails closed on mismatched active/user workspace"
fi

if [ ! -e "$style_root/workspace/users/other-user/.knot/style-pack.md" ] &&
  jq -e 'select(.event == "working_style.pack.denied" and .status == "denied" and .reason_code == "working_style_workspace_mismatch")' "$denied_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style denial creates no pack and records audit event"
else
  fail "working style denial did not preserve fail-closed audit behavior"
fi

ambiguous_root="$TMP_PARENT/working-style-ambiguous-root"
mkdir -p "$ambiguous_root/workspace/admin" "$ambiguous_root/workspace/users" "$ambiguous_root/workspace/conversations/feishu"
cat > "$ambiguous_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| User One | user-one | feishu | ou/ambiguous |  | oc/ambiguous | feishu:user:ambiguous | User One | member | session | smoke |
| User Two | user-two | feishu | ou/ambiguous |  | oc/ambiguous | feishu:user:ambiguous | User Two | member | session | smoke |
EOF
ambiguous_hash="$(sha256_hex_pair feishu "oc/ambiguous")"
ambiguous_conversation_dir="$ambiguous_root/workspace/conversations/feishu/chat_${ambiguous_hash:0:24}"
mkdir -p "$ambiguous_conversation_dir"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$ambiguous_root" \
  --platform feishu \
  --chat-id "oc/ambiguous" \
  --user-id "ou/ambiguous" \
  --identity-key "feishu:user:ambiguous" \
  --actor-user user-one \
  --active-workspace "$ambiguous_root/workspace/users/user-one" \
  --user-workspace "$ambiguous_root/workspace/users/user-one" \
  --conversation-dir "$ambiguous_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack allowed ambiguous permissions identity mapping"
else
  ok "working style pack fails closed on ambiguous permissions identity mapping"
fi

if [ ! -e "$ambiguous_root/workspace/users/user-one/.knot/style-pack.md" ] &&
  jq -e 'select(.event == "working_style.pack.denied" and .status == "denied" and .reason_code == "working_style_identity_ambiguous")' "$ambiguous_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style ambiguous identity denial creates no pack and records audit event"
else
  fail "working style ambiguous identity denial did not preserve fail-closed audit behavior"
fi

mixed_ambiguous_root="$TMP_PARENT/working-style-mixed-ambiguous-root"
mkdir -p "$mixed_ambiguous_root/workspace/admin" "$mixed_ambiguous_root/workspace/users" "$mixed_ambiguous_root/workspace/conversations/feishu"
cat > "$mixed_ambiguous_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| User One | user-one | feishu | ou/mixed |  | oc/mixed | feishu:user:mixed | User One | member | session | smoke |
| User Two | user-two | feishu | ou/mixed |  | oc/mixed | feishu:user:other | User Two | member | session | smoke |
EOF
mixed_hash="$(sha256_hex_pair feishu "oc/mixed")"
mixed_conversation_dir="$mixed_ambiguous_root/workspace/conversations/feishu/chat_${mixed_hash:0:24}"
mkdir -p "$mixed_conversation_dir"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$mixed_ambiguous_root" \
  --platform feishu \
  --chat-id "oc/mixed" \
  --user-id "ou/mixed" \
  --identity-key "feishu:user:mixed" \
  --actor-user user-one \
  --active-workspace "$mixed_ambiguous_root/workspace/users/user-one" \
  --user-workspace "$mixed_ambiguous_root/workspace/users/user-one" \
  --conversation-dir "$mixed_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack allowed ambiguous platform user mapping when identity key was unique"
else
  ok "working style pack fails closed when any provided identity dimension is ambiguous"
fi

if [ ! -e "$mixed_ambiguous_root/workspace/users/user-one/.knot/style-pack.md" ] &&
  jq -e 'select(.event == "working_style.pack.denied" and .status == "denied" and .reason_code == "working_style_identity_ambiguous")' "$mixed_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style mixed ambiguity denial creates no pack and records audit event"
else
  fail "working style mixed ambiguity denial did not preserve fail-closed audit behavior"
fi

missing_permissions_root="$TMP_PARENT/working-style-missing-permissions-root"
mkdir -p "$missing_permissions_root/workspace/users" "$missing_permissions_root/workspace/conversations/feishu"
missing_permissions_hash="$(sha256_hex_pair feishu "oc/missing-permissions")"
missing_permissions_conversation_dir="$missing_permissions_root/workspace/conversations/feishu/chat_${missing_permissions_hash:0:24}"
mkdir -p "$missing_permissions_conversation_dir"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$missing_permissions_root" \
  --platform feishu \
  --chat-id "oc/missing-permissions" \
  --user-id "ou/missing-permissions" \
  --identity-key "feishu:user:missing-permissions" \
  --actor-user missing-permissions \
  --active-workspace "$missing_permissions_root/workspace/users/missing-permissions" \
  --user-workspace "$missing_permissions_root/workspace/users/missing-permissions" \
  --conversation-dir "$missing_permissions_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack allowed missing permissions source of truth"
else
  ok "working style pack fails closed when permissions source of truth is missing"
fi

if [ ! -e "$missing_permissions_root/workspace/users/missing-permissions/.knot/style-pack.md" ] &&
  jq -e 'select(.event == "working_style.pack.denied" and .status == "denied" and .reason_code == "working_style_identity_unresolved")' "$missing_permissions_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style missing permissions denial creates no pack and records audit event"
else
  fail "working style missing permissions denial did not preserve fail-closed audit behavior"
fi

identity_only_root="$TMP_PARENT/working-style-identity-only-root"
mkdir -p "$identity_only_root/workspace/admin" "$identity_only_root/workspace/users" "$identity_only_root/workspace/conversations/feishu"
cat > "$identity_only_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Identity User | identity-user | feishu |  |  | oc/identity-only | stable:identity:user | Identity User | member | session | smoke |
EOF
identity_only_hash="$(sha256_hex_pair feishu "oc/identity-only")"
identity_only_conversation_dir="$identity_only_root/workspace/conversations/feishu/chat_${identity_only_hash:0:24}"
mkdir -p "$identity_only_conversation_dir"
if identity_only_pack="$(bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$identity_only_root" \
  --platform feishu \
  --chat-id "oc/identity-only" \
  --user-id "ou/new-platform-user" \
  --identity-key "stable:identity:user" \
  --actor-user identity-user \
  --active-workspace "$identity_only_root/workspace/users/identity-user" \
  --user-workspace "$identity_only_root/workspace/users/identity-user" \
  --conversation-dir "$identity_only_conversation_dir")" &&
  [ -f "$identity_only_pack" ] &&
  grep -Fq "actor_user: identity-user" "$identity_only_pack"; then
  ok "working style allows unique identity-key mapping without platform-user row"
else
  fail "working style rejected unique identity-key mapping without platform-user row"
fi

symlink_root="$TMP_PARENT/working-style-symlink-root"
symlink_outside="$TMP_PARENT/working-style-symlink-outside"
mkdir -p "$symlink_root/workspace/admin" "$symlink_root/workspace" "$symlink_root/workspace/conversations/feishu" "$symlink_outside"
ln -s "$symlink_outside" "$symlink_root/workspace/users"
cat > "$symlink_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Symlink User | symlink-user | feishu | ou/symlink |  | oc/symlink | feishu:user:symlink | Symlink User | member | session | smoke |
EOF
symlink_hash="$(sha256_hex_pair feishu "oc/symlink")"
symlink_conversation_dir="$symlink_root/workspace/conversations/feishu/chat_${symlink_hash:0:24}"
mkdir -p "$symlink_conversation_dir"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$symlink_root" \
  --platform feishu \
  --chat-id "oc/symlink" \
  --user-id "ou/symlink" \
  --identity-key "feishu:user:symlink" \
  --actor-user symlink-user \
  --active-workspace "$symlink_root/workspace/users/symlink-user" \
  --user-workspace "$symlink_root/workspace/users/symlink-user" \
  --conversation-dir "$symlink_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack allowed symlinked users root"
else
  ok "working style pack fails closed before writing through symlinked users root"
fi

if [ ! -e "$symlink_outside/symlink-user" ] &&
  jq -e 'select(.event == "working_style.pack.denied" and .status == "denied" and .reason_code == "symlink_denied")' "$symlink_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style symlink denial creates no outside files and records audit event"
else
  fail "working style symlink denial wrote outside root or missed audit"
fi

real_root="$TMP_PARENT/working-style-real-root"
root_link="$TMP_PARENT/working-style-root-link"
mkdir -p "$real_root/workspace/admin" "$real_root/workspace/users" "$real_root/workspace/conversations/feishu"
ln -s "$real_root" "$root_link"
cat > "$real_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Root Link User | root-link-user | feishu | ou/root-link |  | oc/root-link | feishu:user:root-link | Root Link User | member | session | smoke |
EOF
root_link_hash="$(sha256_hex_pair feishu "oc/root-link")"
root_link_conversation_dir="$real_root/workspace/conversations/feishu/chat_${root_link_hash:0:24}"
mkdir -p "$root_link_conversation_dir"
if bash "$ROOT/bin/knot-working-style-pack.sh" pack \
  --root "$root_link" \
  --platform feishu \
  --chat-id "oc/root-link" \
  --user-id "ou/root-link" \
  --identity-key "feishu:user:root-link" \
  --actor-user root-link-user \
  --active-workspace "$root_link/workspace/users/root-link-user" \
  --user-workspace "$root_link/workspace/users/root-link-user" \
  --conversation-dir "$root_link_conversation_dir" >/dev/null 2>&1; then
  fail "working style pack allowed symlinked Knot root"
else
  ok "working style pack rejects symlinked Knot root explicitly"
fi

if [ ! -e "$real_root/workspace/users/root-link-user/.knot/style-pack.md" ] &&
  jq -e 'select(.event == "working_style.pack.denied" and .status == "denied" and .reason_code == "symlink_denied")' "$root_link_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style symlink root denial creates no pack and records audit event"
else
  fail "working style symlink root denial wrote pack or missed audit"
fi

chmod 644 "$style_file"
if pack_working_style >/dev/null &&
  [ "$(mode_of "$style_file")" = "600" ]; then
  ok "working style pack tightens existing style file permissions"
else
  fail "working style pack did not tighten existing style file permissions"
fi

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,1 +9,2 @@
 - Prefers concise status updates with concrete verification evidence.
+- Prefers direct technical challenge when assumptions look weak.
EOF

if apply_working_style_patch >/dev/null &&
  grep -Fq "Prefers direct technical challenge" "$style_file" &&
  [ "$(mode_of "$style_file")" = "600" ] &&
  [ "$(mode_of "$style_patch_file")" = "600" ] &&
  jq -e 'select(.event == "working_style.patch.applied" and .status == "recorded")' "$style_conversation_dir/events.jsonl" >/dev/null; then
  ok "working style atomically applies authorized style patch"
else
  fail "working style did not apply authorized style patch"
fi

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -1,10 +1,2 @@
----
-version: 1
-updated: 2026-01-01
-reviewed: 2026-01-01
----
-# Working Style
-
-## Communication
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
EOF
assert_style_patch_denied_unchanged \
  "working style rejects patch output that removes structured schema" \
  working_style_content_denied

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+- Audit failure must not land.
EOF

style_before_audit_failure="$(file_sha256 "$style_file")"
if bash "$ROOT/bin/knot-working-style-apply.sh" apply \
  --root "$style_root" \
  --patch "$style_patch_file" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$style_user_workspace" \
  --user-workspace "$style_user_workspace" \
  --conversation-dir "$invalid_audit_dir" >/dev/null 2>&1; then
  fail "working style apply allowed mutation without a valid audit event"
elif [ "$(file_sha256 "$style_file")" = "$style_before_audit_failure" ] &&
  ! grep -Fq "Audit failure must not land" "$style_file"; then
  ok "working style apply rolls back when audit event cannot be recorded"
else
  fail "working style apply left mutation after audit failure"
fi

write_style_patch "$style_target_rel" "0000000000000000000000000000000000000000000000000000000000000000" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ stale write must not land.
EOF
assert_style_patch_denied_unchanged \
  "working style rejects stale patch without modifying target" \
  working_style_patch_conflict

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ concurrent write must not land.
EOF
mkdir "$style_user_workspace/.knot/style-apply.lock"
assert_style_patch_denied_unchanged \
  "working style rejects concurrent working style apply lock" \
  working_style_patch_conflict
rmdir "$style_user_workspace/.knot/style-apply.lock"

write_style_patch "workspace/users/direct-user/../memory/style.md" "$style_base" <<EOF
--- a/workspace/users/direct-user/../memory/style.md
+++ b/workspace/users/direct-user/../memory/style.md
@@ -1,1 +1,2 @@
 # Working Style
+ traversal must not land.
EOF
assert_style_patch_denied_unchanged \
  "working style rejects traversal patch target" \
  working_style_patch_invalid

write_style_patch "$style_file" "$style_base" <<EOF
--- a/$style_file
+++ b/$style_file
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ absolute path must not land.
EOF
assert_style_patch_denied_unchanged \
  "working style rejects absolute patch target" \
  working_style_patch_invalid

write_style_patch "workspace/users/direct-user/notes.md" "$style_base" <<EOF
--- a/workspace/users/direct-user/notes.md
+++ b/workspace/users/direct-user/notes.md
@@ -1,1 +1,2 @@
 # Notes
+ non-style target must not land.
EOF
assert_style_patch_denied_unchanged \
  "working style rejects non-style patch target" \
  working_style_patch_invalid

write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -99,1 +99,2 @@
 - nonexistent patch source
+ malformed diff must not land.
EOF
assert_style_patch_denied_unchanged \
  "working style rejects malformed unified diff without modifying target" \
  working_style_patch_invalid

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,4 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+\`\`\`transcript
+User: copy raw chat
EOF
assert_style_patch_denied_unchanged \
  "working style rejects explicit transcript blocks" \
  working_style_content_denied

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+API_KEY=secret-value
EOF
assert_style_patch_denied_unchanged \
  "working style rejects secrets-looking additions" \
  working_style_content_denied

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+- access_token=secret-value
EOF
assert_style_patch_denied_unchanged \
  "working style rejects bullet secrets-looking additions" \
  working_style_content_denied

style_base="$(file_sha256 "$style_file")"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+\`\`\`source-document
EOF
assert_style_patch_denied_unchanged \
  "working style rejects copied source-document blocks" \
  working_style_content_denied

style_base="$(file_sha256 "$style_file")"
long_style_line="$(printf 'x%.0s' $(seq 1 1700))"
write_style_patch "$style_target_rel" "$style_base" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+$long_style_line
EOF
assert_style_patch_denied_unchanged \
  "working style rejects oversized style output" \
  working_style_content_denied

style_before="$(file_sha256 "$style_file")"
style_mismatch_before="$(style_denied_count "$style_conversation_dir" working_style.patch.denied working_style_workspace_mismatch)"
if bash "$ROOT/bin/knot-working-style-apply.sh" apply \
  --root "$style_root" \
  --patch "$style_patch_file" \
  --platform feishu \
  --chat-id "oc/direct-style" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user other-user \
  --active-workspace "$style_root/workspace/users/other-user" \
  --user-workspace "$style_root/workspace/users/other-user" \
  --conversation-dir "$style_conversation_dir" >/dev/null 2>&1; then
  fail "working style allowed patch for mismatched actor identity"
elif [ "$(file_sha256 "$style_file")" = "$style_before" ] &&
  [ "$(style_denied_count "$style_conversation_dir" working_style.patch.denied working_style_workspace_mismatch)" -gt "$style_mismatch_before" ]; then
  ok "working style apply fails closed for mismatched actor identity"
else
  fail "working style mismatch denial did not preserve target and audit"
fi

style_symlink_outside="$TMP_PARENT/working-style-outside.md"
cp "$style_file" "$style_symlink_outside"
rm "$style_file"
ln -s "$style_symlink_outside" "$style_file"
write_style_patch "$style_target_rel" "$(file_sha256 "$style_symlink_outside")" <<EOF
--- a/$style_target_rel
+++ b/$style_target_rel
@@ -9,2 +9,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ symlink write must not land.
EOF
before_outside="$(file_sha256 "$style_symlink_outside")"
before_symlink_events="$(style_denied_count "$style_conversation_dir" working_style.patch.denied symlink_denied)"
if apply_working_style_patch >/dev/null 2>&1; then
  fail "working style rejects symlink style target"
elif [ "$(file_sha256 "$style_symlink_outside")" = "$before_outside" ] &&
  [ "$(style_denied_count "$style_conversation_dir" working_style.patch.denied symlink_denied)" -gt "$before_symlink_events" ]; then
  ok "working style rejects symlink style target"
else
  fail "working style symlink denial did not preserve target and audit"
fi

assert_event_schema "$style_conversation_dir/events.jsonl"
assert_event_schema "$group_style_conversation_dir/events.jsonl"
assert_event_schema "$denied_conversation_dir/events.jsonl"
assert_event_schema "$ambiguous_conversation_dir/events.jsonl"
assert_event_schema "$mixed_conversation_dir/events.jsonl"
assert_event_schema "$missing_permissions_conversation_dir/events.jsonl"
assert_event_schema "$identity_only_conversation_dir/events.jsonl"
assert_event_schema "$symlink_conversation_dir/events.jsonl"
assert_event_schema "$root_link_conversation_dir/events.jsonl"
