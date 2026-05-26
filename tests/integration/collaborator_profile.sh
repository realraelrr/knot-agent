# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

mode_of() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

profile_denied_count() {
  local conversation_dir="$1"
  local event="$2"
  local reason="$3"

  jq -s --arg event "$event" --arg reason "$reason" \
    '[.[] | select(.event == $event and .reason_code == $reason)] | length' \
    "$conversation_dir/events.jsonl"
}

profile_root="$TMP_PARENT/collaborator-profile-root"
mkdir -p "$profile_root/workspace/admin"
cat > "$profile_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Direct User | direct-user | feishu | ou/direct-user |  | oc/direct-profile | feishu:user:direct | Direct User | member | session | smoke |
| Direct User | direct-user | feishu | ou/direct-user | profile-group | oc/group-profile | feishu:user:direct | Direct User | member | session | smoke |
EOF

profile_workspace_exports="$(bash "$ROOT/bin/knot-workspace.sh" \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --user-slug "direct-user" \
  --identity-key "feishu:user:direct" \
  --emit-conversation-initialized)" || {
  fail "knot-workspace setup for collaborator profile tests failed"
  exit 1
}
eval "$profile_workspace_exports"

profile_user_workspace="$KNOT_USER_WORKSPACE"
profile_conversation_dir="$KNOT_CONVERSATION_DIR"
profile_dir="$profile_user_workspace/collaboration"
profile_file="$profile_dir/profile.md"
profile_pack_file="$profile_user_workspace/.knot/collaborator-profile-pack.md"
profile_patch_file="$profile_user_workspace/.knot/collaborator-profile.patch"
profile_target_rel="workspace/users/direct-user/collaboration/profile.md"

mkdir -p "$profile_dir"
cat > "$profile_file" <<'EOF'
# Collaborator Profile

- Prefers concise status updates with concrete verification evidence.
EOF

pack_collaborator_profile() {
  bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
    --root "$profile_root" \
    --platform feishu \
    --chat-id "oc/direct-profile" \
    --user-id "ou/direct-user" \
    --identity-key "feishu:user:direct" \
    --actor-user direct-user \
    --scope direct \
    --active-workspace "$profile_user_workspace" \
    --user-workspace "$profile_user_workspace" \
    --actor-workspace "$profile_user_workspace" \
    --conversation-dir "$profile_conversation_dir"
}

apply_collaborator_profile_patch() {
  bash "$ROOT/bin/knot-collaborator-profile-apply.sh" apply \
    --root "$profile_root" \
    --patch "$profile_patch_file" \
    --platform feishu \
    --chat-id "oc/direct-profile" \
    --user-id "ou/direct-user" \
    --identity-key "feishu:user:direct" \
    --actor-user direct-user \
    --scope direct \
    --active-workspace "$profile_user_workspace" \
    --user-workspace "$profile_user_workspace" \
    --actor-workspace "$profile_user_workspace" \
    --conversation-dir "$profile_conversation_dir"
}

assert_profile_patch_denied_unchanged() {
  local label="$1"
  local expected_reason="$2"
  local before_hash
  local before_events
  local after_events

  before_hash="$(file_sha256 "$profile_file")"
  before_events="$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied "$expected_reason")"
  if apply_collaborator_profile_patch >/dev/null 2>&1; then
    fail "$label"
    return
  fi
  after_events="$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied "$expected_reason")"
  if [ "$(file_sha256 "$profile_file")" = "$before_hash" ] &&
    [ "$after_events" -gt "$before_events" ]; then
    ok "$label"
  else
    fail "$label"
  fi
}

if profile_pack_path="$(pack_collaborator_profile)" &&
  [ "$(absolute_path "$profile_pack_path")" = "$(absolute_path "$profile_pack_file")" ] &&
  [ -f "$profile_pack_file" ] &&
  grep -Fq "Knot Collaborator Profile Pack" "$profile_pack_file" &&
  grep -Fq "actor_user: direct-user" "$profile_pack_file" &&
  grep -Fq "write_target: workspace/users/direct-user/collaboration/profile.md" "$profile_pack_file" &&
  grep -Fq "Prefers concise status updates" "$profile_pack_file" &&
  [ "$(mode_of "$profile_pack_file")" = "600" ] &&
  [ "$(mode_of "$profile_file")" = "600" ] &&
  [ ! -e "$profile_user_workspace/memory/active.md" ] &&
  [ ! -e "$profile_user_workspace/memory/followups.md" ]; then
  ok "collaborator profile pack creates only owner-only collaboration profile context"
else
  fail "collaborator profile pack did not create expected bounded context"
fi

if [ -f "$profile_pack_file" ]; then
  first_pack_hash="$(file_sha256 "$profile_pack_file")"
  if second_pack_path="$(pack_collaborator_profile)" &&
    [ "$(absolute_path "$second_pack_path")" = "$(absolute_path "$profile_pack_file")" ] &&
    [ "$(file_sha256 "$profile_pack_file")" = "$first_pack_hash" ]; then
    ok "collaborator profile pack output is deterministic for unchanged inputs"
  else
    fail "collaborator profile pack output changed for unchanged inputs"
  fi
else
  fail "collaborator profile pack output is deterministic for unchanged inputs"
fi

if jq -e 'select(.event == "collab.profile.pack.generated" and .status == "recorded")' "$profile_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile pack records compact audit event"
else
  fail "collaborator profile pack did not record compact audit event"
fi

group_profile_exports="$(bash "$ROOT/bin/knot-workspace.sh" \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/group-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --emit-conversation-initialized)" || {
  fail "knot-workspace setup for group collaborator profile tests failed"
  exit 1
}
eval "$group_profile_exports"
group_profile_active_workspace="$KNOT_ACTIVE_WORKSPACE"
group_profile_actor_workspace="${KNOT_ACTOR_WORKSPACE:-}"
group_profile_user_workspace="$KNOT_USER_WORKSPACE"
group_profile_conversation_dir="$KNOT_CONVERSATION_DIR"
group_profile_pack_file="$group_profile_actor_workspace/.knot/collaborator-profile-pack.md"
group_profile_patch_file="$group_profile_actor_workspace/.knot/collaborator-profile.patch"

if group_profile_pack_path="$(bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/group-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug profile-group \
  --active-workspace "$group_profile_active_workspace" \
  --user-workspace "$group_profile_user_workspace" \
  --actor-workspace "$group_profile_actor_workspace" \
  --conversation-dir "$group_profile_conversation_dir")" &&
  [ "$(absolute_path "$group_profile_pack_path")" = "$(absolute_path "$group_profile_pack_file")" ] &&
  [ -f "$group_profile_pack_file" ] &&
  grep -Fq "scope: collaborator_profile" "$group_profile_pack_file" &&
  grep -Fq "mode: read_only" "$group_profile_pack_file" &&
  grep -Fq "active_workspace: workspace/groups/profile-group" "$group_profile_pack_file" &&
  grep -Fq "actor_workspace: workspace/groups/profile-group/work/direct-user" "$group_profile_pack_file" &&
  grep -Fq "source_profile: workspace/users/direct-user/collaboration/profile.md" "$group_profile_pack_file" &&
  grep -Fq "Prefers concise status updates" "$group_profile_pack_file" &&
  [ "$(mode_of "$group_profile_pack_file")" = "600" ]; then
  ok "collaborator profile group scope writes read-only pack to actor lane"
else
  fail "collaborator profile group scope did not write expected read-only pack"
fi

group_profile_base="$(file_sha256 "$profile_file")"
cat > "$group_profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $group_profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,1 +3,2 @@
 - Prefers concise status updates with concrete verification evidence.
+- group chat must not silently write profile changes.
EOF
before_group_apply_hash="$(file_sha256 "$profile_file")"
before_group_apply_denials="$(profile_denied_count "$group_profile_conversation_dir" collab.profile.patch.denied collab_profile_workspace_mismatch)"
if bash "$ROOT/bin/knot-collaborator-profile-apply.sh" apply \
  --root "$profile_root" \
  --patch "$group_profile_patch_file" \
  --platform feishu \
  --chat-id "oc/group-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug profile-group \
  --active-workspace "$group_profile_active_workspace" \
  --user-workspace "$group_profile_user_workspace" \
  --actor-workspace "$group_profile_actor_workspace" \
  --conversation-dir "$group_profile_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile apply allowed group scope mutation"
elif [ "$(file_sha256 "$profile_file")" = "$before_group_apply_hash" ] &&
  [ "$(profile_denied_count "$group_profile_conversation_dir" collab.profile.patch.denied collab_profile_workspace_mismatch)" -gt "$before_group_apply_denials" ]; then
  ok "collaborator profile apply rejects group scope mutation"
else
  fail "collaborator profile group scope apply did not preserve target and audit"
fi

before_implicit_group_pack_denials="$(profile_denied_count "$profile_conversation_dir" collab.profile.pack.denied collab_profile_workspace_mismatch)"
if env KNOT_SCOPE= bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug profile-group \
  --active-workspace "$profile_user_workspace" \
  --user-workspace "$profile_user_workspace" \
  --conversation-dir "$profile_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack inferred direct scope despite group slug"
elif [ "$(profile_denied_count "$profile_conversation_dir" collab.profile.pack.denied collab_profile_workspace_mismatch)" -gt "$before_implicit_group_pack_denials" ]; then
  ok "collaborator profile pack rejects missing scope with group slug"
else
  fail "collaborator profile pack missing-scope group slug denial was not audited"
fi

before_direct_group_pack_denials="$(profile_denied_count "$profile_conversation_dir" collab.profile.pack.denied collab_profile_workspace_mismatch)"
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug profile-group \
  --scope direct \
  --active-workspace "$profile_user_workspace" \
  --user-workspace "$profile_user_workspace" \
  --conversation-dir "$profile_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed direct scope with group slug"
elif [ "$(profile_denied_count "$profile_conversation_dir" collab.profile.pack.denied collab_profile_workspace_mismatch)" -gt "$before_direct_group_pack_denials" ]; then
  ok "collaborator profile pack rejects direct scope with group slug"
else
  fail "collaborator profile pack direct-scope group slug denial was not audited"
fi

implicit_group_apply_backup="$profile_dir/.implicit-group-apply.backup"
cp "$profile_file" "$implicit_group_apply_backup"
implicit_group_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $implicit_group_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,1 +3,2 @@
 - Prefers concise status updates with concrete verification evidence.
+- implicit group scope must not write profile changes.
EOF
before_implicit_group_apply_denials="$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied collab_profile_workspace_mismatch)"
if env KNOT_SCOPE= bash "$ROOT/bin/knot-collaborator-profile-apply.sh" apply \
  --root "$profile_root" \
  --patch "$profile_patch_file" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --group-slug profile-group \
  --active-workspace "$profile_user_workspace" \
  --user-workspace "$profile_user_workspace" \
  --conversation-dir "$profile_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile apply inferred direct scope despite group slug"
  mv "$implicit_group_apply_backup" "$profile_file"
  chmod 600 "$profile_file"
elif [ "$(file_sha256 "$profile_file")" = "$implicit_group_base" ] &&
  [ "$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied collab_profile_workspace_mismatch)" -gt "$before_implicit_group_apply_denials" ]; then
  ok "collaborator profile apply rejects missing scope with group slug"
  rm -f "$implicit_group_apply_backup"
else
  fail "collaborator profile apply missing-scope group slug denial did not preserve target and audit"
  mv "$implicit_group_apply_backup" "$profile_file"
  chmod 600 "$profile_file"
fi
eval "$profile_workspace_exports"

assert_profile_pack_denied_existing_content() {
  local label="$1"
  local content="$2"
  local profile_backup="$profile_dir/.profile.backup"
  local pack_backup="$profile_user_workspace/.knot/.pack.backup"
  local before_events
  local after_events
  local before_pack_hash

  cp "$profile_file" "$profile_backup"
  cp "$profile_pack_file" "$pack_backup"
  printf '%s' "$content" > "$profile_file"
  chmod 600 "$profile_file"
  before_pack_hash="$(file_sha256 "$profile_pack_file")"
  before_events="$(profile_denied_count "$profile_conversation_dir" collab.profile.pack.denied collab_profile_content_denied)"

  if pack_collaborator_profile >/dev/null 2>&1; then
    fail "$label"
  else
    after_events="$(profile_denied_count "$profile_conversation_dir" collab.profile.pack.denied collab_profile_content_denied)"
    if [ "$(file_sha256 "$profile_pack_file")" = "$before_pack_hash" ] &&
      [ "$after_events" -gt "$before_events" ]; then
      ok "$label"
    else
      fail "$label"
    fi
  fi

  mv "$profile_backup" "$profile_file"
  mv "$pack_backup" "$profile_pack_file"
  chmod 600 "$profile_file" "$profile_pack_file"
}

assert_profile_pack_denied_existing_content \
  "collaborator profile pack rejects existing transcript blocks" \
  $'# Collaborator Profile\n\n```transcript\nUser: copied raw chat\n'
assert_profile_pack_denied_existing_content \
  "collaborator profile pack rejects existing secrets-looking content" \
  $'# Collaborator Profile\n\nAPI_KEY=secret-value\n'
assert_profile_pack_denied_existing_content \
  "collaborator profile pack rejects existing bullet secrets-looking content" \
  $'# Collaborator Profile\n\n- password: hunter2\n'
long_existing_profile="$(printf 'x%.0s' $(seq 1 1700))"
assert_profile_pack_denied_existing_content \
  "collaborator profile pack rejects existing oversized content" \
  "# Collaborator Profile

$long_existing_profile
"

if env -u KNOT_CONVERSATION_DIR bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$profile_user_workspace" \
  --user-workspace "$profile_user_workspace" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed generation without conversation audit target"
else
  ok "collaborator profile pack requires conversation audit target"
fi

invalid_audit_dir="$profile_root/workspace/conversations/feishu/not_chat"
mkdir -p "$invalid_audit_dir"
before_pack_hash="$(file_sha256 "$profile_pack_file")"
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$profile_user_workspace" \
  --user-workspace "$profile_user_workspace" \
  --conversation-dir "$invalid_audit_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed generation without a valid audit event"
elif [ "$(file_sha256 "$profile_pack_file")" = "$before_pack_hash" ] &&
  [ ! -e "$invalid_audit_dir/events.jsonl" ]; then
  ok "collaborator profile pack fails closed when audit event cannot be recorded"
else
  fail "collaborator profile pack changed runtime pack after audit failure"
fi

denied_hash="$(sha256_hex_pair feishu "oc/profile-denied")"
denied_conversation_dir="$profile_root/workspace/conversations/feishu/chat_${denied_hash:0:24}"
mkdir -p "$denied_conversation_dir"
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$profile_root" \
  --platform feishu \
  --chat-id "oc/profile-denied" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$profile_root/workspace/users/other-user" \
  --user-workspace "$profile_user_workspace" \
  --conversation-dir "$denied_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed mismatched active/user workspace"
else
  ok "collaborator profile pack fails closed on mismatched active/user workspace"
fi

if [ ! -e "$profile_root/workspace/users/other-user/.knot/collaborator-profile-pack.md" ] &&
  jq -e 'select(.event == "collab.profile.pack.denied" and .status == "denied" and .reason_code == "collab_profile_workspace_mismatch")' "$denied_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile denial creates no pack and records audit event"
else
  fail "collaborator profile denial did not preserve fail-closed audit behavior"
fi

ambiguous_root="$TMP_PARENT/collaborator-profile-ambiguous-root"
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
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$ambiguous_root" \
  --platform feishu \
  --chat-id "oc/ambiguous" \
  --user-id "ou/ambiguous" \
  --identity-key "feishu:user:ambiguous" \
  --actor-user user-one \
  --active-workspace "$ambiguous_root/workspace/users/user-one" \
  --user-workspace "$ambiguous_root/workspace/users/user-one" \
  --conversation-dir "$ambiguous_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed ambiguous permissions identity mapping"
else
  ok "collaborator profile pack fails closed on ambiguous permissions identity mapping"
fi

if [ ! -e "$ambiguous_root/workspace/users/user-one/.knot/collaborator-profile-pack.md" ] &&
  jq -e 'select(.event == "collab.profile.pack.denied" and .status == "denied" and .reason_code == "collab_profile_identity_ambiguous")' "$ambiguous_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile ambiguous identity denial creates no pack and records audit event"
else
  fail "collaborator profile ambiguous identity denial did not preserve fail-closed audit behavior"
fi

mixed_ambiguous_root="$TMP_PARENT/collaborator-profile-mixed-ambiguous-root"
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
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$mixed_ambiguous_root" \
  --platform feishu \
  --chat-id "oc/mixed" \
  --user-id "ou/mixed" \
  --identity-key "feishu:user:mixed" \
  --actor-user user-one \
  --active-workspace "$mixed_ambiguous_root/workspace/users/user-one" \
  --user-workspace "$mixed_ambiguous_root/workspace/users/user-one" \
  --conversation-dir "$mixed_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed ambiguous platform user mapping when identity key was unique"
else
  ok "collaborator profile pack fails closed when any provided identity dimension is ambiguous"
fi

if [ ! -e "$mixed_ambiguous_root/workspace/users/user-one/.knot/collaborator-profile-pack.md" ] &&
  jq -e 'select(.event == "collab.profile.pack.denied" and .status == "denied" and .reason_code == "collab_profile_identity_ambiguous")' "$mixed_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile mixed ambiguity denial creates no pack and records audit event"
else
  fail "collaborator profile mixed ambiguity denial did not preserve fail-closed audit behavior"
fi

missing_permissions_root="$TMP_PARENT/collaborator-profile-missing-permissions-root"
mkdir -p "$missing_permissions_root/workspace/users" "$missing_permissions_root/workspace/conversations/feishu"
missing_permissions_hash="$(sha256_hex_pair feishu "oc/missing-permissions")"
missing_permissions_conversation_dir="$missing_permissions_root/workspace/conversations/feishu/chat_${missing_permissions_hash:0:24}"
mkdir -p "$missing_permissions_conversation_dir"
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$missing_permissions_root" \
  --platform feishu \
  --chat-id "oc/missing-permissions" \
  --user-id "ou/missing-permissions" \
  --identity-key "feishu:user:missing-permissions" \
  --actor-user missing-permissions \
  --active-workspace "$missing_permissions_root/workspace/users/missing-permissions" \
  --user-workspace "$missing_permissions_root/workspace/users/missing-permissions" \
  --conversation-dir "$missing_permissions_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed missing permissions source of truth"
else
  ok "collaborator profile pack fails closed when permissions source of truth is missing"
fi

if [ ! -e "$missing_permissions_root/workspace/users/missing-permissions/.knot/collaborator-profile-pack.md" ] &&
  jq -e 'select(.event == "collab.profile.pack.denied" and .status == "denied" and .reason_code == "collab_profile_identity_unresolved")' "$missing_permissions_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile missing permissions denial creates no pack and records audit event"
else
  fail "collaborator profile missing permissions denial did not preserve fail-closed audit behavior"
fi

identity_only_root="$TMP_PARENT/collaborator-profile-identity-only-root"
mkdir -p "$identity_only_root/workspace/admin" "$identity_only_root/workspace/users" "$identity_only_root/workspace/conversations/feishu"
cat > "$identity_only_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Identity User | identity-user | feishu |  |  | oc/identity-only | stable:identity:user | Identity User | member | session | smoke |
EOF
identity_only_hash="$(sha256_hex_pair feishu "oc/identity-only")"
identity_only_conversation_dir="$identity_only_root/workspace/conversations/feishu/chat_${identity_only_hash:0:24}"
mkdir -p "$identity_only_conversation_dir"
if identity_only_pack="$(bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
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
  ok "collaborator profile allows unique identity-key mapping without platform-user row"
else
  fail "collaborator profile rejected unique identity-key mapping without platform-user row"
fi

symlink_root="$TMP_PARENT/collaborator-profile-symlink-root"
symlink_outside="$TMP_PARENT/collaborator-profile-symlink-outside"
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
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$symlink_root" \
  --platform feishu \
  --chat-id "oc/symlink" \
  --user-id "ou/symlink" \
  --identity-key "feishu:user:symlink" \
  --actor-user symlink-user \
  --active-workspace "$symlink_root/workspace/users/symlink-user" \
  --user-workspace "$symlink_root/workspace/users/symlink-user" \
  --conversation-dir "$symlink_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed symlinked users root"
else
  ok "collaborator profile pack fails closed before writing through symlinked users root"
fi

if [ ! -e "$symlink_outside/symlink-user" ] &&
  jq -e 'select(.event == "collab.profile.pack.denied" and .status == "denied" and .reason_code == "symlink_denied")' "$symlink_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile symlink denial creates no outside files and records audit event"
else
  fail "collaborator profile symlink denial wrote outside root or missed audit"
fi

real_root="$TMP_PARENT/collaborator-profile-real-root"
root_link="$TMP_PARENT/collaborator-profile-root-link"
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
if bash "$ROOT/bin/knot-collaborator-profile-pack.sh" pack \
  --root "$root_link" \
  --platform feishu \
  --chat-id "oc/root-link" \
  --user-id "ou/root-link" \
  --identity-key "feishu:user:root-link" \
  --actor-user root-link-user \
  --active-workspace "$root_link/workspace/users/root-link-user" \
  --user-workspace "$root_link/workspace/users/root-link-user" \
  --conversation-dir "$root_link_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile pack allowed symlinked Knot root"
else
  ok "collaborator profile pack rejects symlinked Knot root explicitly"
fi

if [ ! -e "$real_root/workspace/users/root-link-user/.knot/collaborator-profile-pack.md" ] &&
  jq -e 'select(.event == "collab.profile.pack.denied" and .status == "denied" and .reason_code == "symlink_denied")' "$root_link_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile symlink root denial creates no pack and records audit event"
else
  fail "collaborator profile symlink root denial wrote pack or missed audit"
fi

chmod 644 "$profile_file"
if pack_collaborator_profile >/dev/null &&
  [ "$(mode_of "$profile_file")" = "600" ]; then
  ok "collaborator profile pack tightens existing profile file permissions"
else
  fail "collaborator profile pack did not tighten existing profile file permissions"
fi

profile_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,1 +3,2 @@
 - Prefers concise status updates with concrete verification evidence.
+- Prefers direct technical challenge when assumptions look weak.
EOF

if apply_collaborator_profile_patch >/dev/null &&
  grep -Fq "Prefers direct technical challenge" "$profile_file" &&
  [ "$(mode_of "$profile_file")" = "600" ] &&
  [ "$(mode_of "$profile_patch_file")" = "600" ] &&
  jq -e 'select(.event == "collab.profile.patch.applied" and .status == "recorded")' "$profile_conversation_dir/events.jsonl" >/dev/null; then
  ok "collaborator profile atomically applies authorized profile patch"
else
  fail "collaborator profile did not apply authorized profile patch"
fi

profile_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+- Audit failure must not land.
EOF

profile_before_audit_failure="$(file_sha256 "$profile_file")"
if bash "$ROOT/bin/knot-collaborator-profile-apply.sh" apply \
  --root "$profile_root" \
  --patch "$profile_patch_file" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$profile_user_workspace" \
  --user-workspace "$profile_user_workspace" \
  --conversation-dir "$invalid_audit_dir" >/dev/null 2>&1; then
  fail "collaborator profile apply allowed mutation without a valid audit event"
elif [ "$(file_sha256 "$profile_file")" = "$profile_before_audit_failure" ] &&
  ! grep -Fq "Audit failure must not land" "$profile_file"; then
  ok "collaborator profile apply rolls back when audit event cannot be recorded"
else
  fail "collaborator profile apply left mutation after audit failure"
fi

cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: 0000000000000000000000000000000000000000000000000000000000000000

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ stale write must not land.
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects stale patch without modifying target" \
  collab_profile_patch_conflict

profile_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ concurrent write must not land.
EOF
mkdir "$profile_user_workspace/.knot/collaborator-profile-apply.lock"
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects concurrent profile apply lock" \
  collab_profile_patch_conflict
rmdir "$profile_user_workspace/.knot/collaborator-profile-apply.lock"

cat > "$profile_patch_file" <<EOF
target: workspace/users/direct-user/collaboration/../memory/profile.md
base_sha256: $profile_base

--- a/workspace/users/direct-user/collaboration/../memory/profile.md
+++ b/workspace/users/direct-user/collaboration/../memory/profile.md
@@ -1,1 +1,2 @@
 # Collaborator Profile
+ traversal must not land.
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects traversal patch target" \
  collab_profile_patch_invalid

cat > "$profile_patch_file" <<EOF
target: $profile_file
base_sha256: $profile_base

--- a/$profile_file
+++ b/$profile_file
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ absolute path must not land.
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects absolute patch target" \
  collab_profile_patch_invalid

cat > "$profile_patch_file" <<EOF
target: workspace/users/direct-user/collaboration/notes.md
base_sha256: $profile_base

--- a/workspace/users/direct-user/collaboration/notes.md
+++ b/workspace/users/direct-user/collaboration/notes.md
@@ -1,1 +1,2 @@
 # Notes
+ non-profile target must not land.
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects non-profile patch target" \
  collab_profile_patch_invalid

cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -99,1 +99,2 @@
 - nonexistent patch source
+ malformed diff must not land.
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects malformed unified diff without modifying target" \
  collab_profile_patch_invalid

profile_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,4 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+\`\`\`transcript
+User: copy raw chat
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects explicit transcript blocks" \
  collab_profile_content_denied

profile_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+API_KEY=secret-value
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects secrets-looking additions" \
  collab_profile_content_denied

profile_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+- access_token=secret-value
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects bullet secrets-looking additions" \
  collab_profile_content_denied

profile_base="$(file_sha256 "$profile_file")"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+\`\`\`source-document
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects copied source-document blocks" \
  collab_profile_content_denied

profile_base="$(file_sha256 "$profile_file")"
long_profile_line="$(printf 'x%.0s' $(seq 1 1700))"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $profile_base

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+$long_profile_line
EOF
assert_profile_patch_denied_unchanged \
  "collaborator profile rejects oversized profile output" \
  collab_profile_content_denied

profile_before="$(file_sha256 "$profile_file")"
profile_mismatch_before="$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied collab_profile_workspace_mismatch)"
if bash "$ROOT/bin/knot-collaborator-profile-apply.sh" apply \
  --root "$profile_root" \
  --patch "$profile_patch_file" \
  --platform feishu \
  --chat-id "oc/direct-profile" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user other-user \
  --active-workspace "$profile_root/workspace/users/other-user" \
  --user-workspace "$profile_root/workspace/users/other-user" \
  --conversation-dir "$profile_conversation_dir" >/dev/null 2>&1; then
  fail "collaborator profile allowed patch for mismatched actor identity"
elif [ "$(file_sha256 "$profile_file")" = "$profile_before" ] &&
  [ "$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied collab_profile_workspace_mismatch)" -gt "$profile_mismatch_before" ]; then
  ok "collaborator profile apply fails closed for mismatched actor identity"
else
  fail "collaborator profile mismatch denial did not preserve target and audit"
fi

profile_symlink_outside="$TMP_PARENT/collaborator-profile-outside.md"
cp "$profile_file" "$profile_symlink_outside"
rm "$profile_file"
ln -s "$profile_symlink_outside" "$profile_file"
cat > "$profile_patch_file" <<EOF
target: $profile_target_rel
base_sha256: $(file_sha256 "$profile_symlink_outside")

--- a/$profile_target_rel
+++ b/$profile_target_rel
@@ -3,2 +3,3 @@
 - Prefers concise status updates with concrete verification evidence.
 - Prefers direct technical challenge when assumptions look weak.
+ symlink write must not land.
EOF
before_outside="$(file_sha256 "$profile_symlink_outside")"
before_symlink_events="$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied symlink_denied)"
if apply_collaborator_profile_patch >/dev/null 2>&1; then
  fail "collaborator profile rejects symlink profile target"
elif [ "$(file_sha256 "$profile_symlink_outside")" = "$before_outside" ] &&
  [ "$(profile_denied_count "$profile_conversation_dir" collab.profile.patch.denied symlink_denied)" -gt "$before_symlink_events" ]; then
  ok "collaborator profile rejects symlink profile target"
else
  fail "collaborator profile symlink denial did not preserve target and audit"
fi

assert_event_schema "$profile_conversation_dir/events.jsonl"
assert_event_schema "$group_profile_conversation_dir/events.jsonl"
assert_event_schema "$denied_conversation_dir/events.jsonl"
assert_event_schema "$ambiguous_conversation_dir/events.jsonl"
assert_event_schema "$mixed_conversation_dir/events.jsonl"
assert_event_schema "$missing_permissions_conversation_dir/events.jsonl"
assert_event_schema "$identity_only_conversation_dir/events.jsonl"
assert_event_schema "$symlink_conversation_dir/events.jsonl"
assert_event_schema "$root_link_conversation_dir/events.jsonl"
