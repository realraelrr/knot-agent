# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

mode_of() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

memory_root="$TMP_PARENT/memory-root"
mkdir -p "$memory_root/workspace/admin"
cat > "$memory_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Direct User | direct-user | feishu | ou/direct-user |  | oc/direct-memory | feishu:user:direct | Direct User | member | session | smoke |
EOF

memory_workspace_exports="$(bash "$ROOT/bin/knot-workspace.sh" \
  --root "$memory_root" \
  --platform feishu \
  --chat-id "oc/direct-memory" \
  --user-id "ou/direct-user" \
  --user-slug "direct-user" \
  --identity-key "feishu:user:direct" \
  --emit-conversation-initialized)" || {
  fail "knot-workspace setup for memory tests failed"
  exit 1
}
eval "$memory_workspace_exports"

memory_user_workspace="$KNOT_USER_WORKSPACE"
memory_conversation_dir="$KNOT_CONVERSATION_DIR"
mkdir -p "$memory_user_workspace/memory"
cat > "$memory_user_workspace/memory/profile.md" <<'EOF'
# Profile

- Role: release operator for Knot.
EOF
cat > "$memory_user_workspace/memory/active.md" <<'EOF'
# Active

- 2026-05-26: Validate direct-chat memory pack.
EOF
cat > "$memory_user_workspace/memory/followups.md" <<'EOF'
# Followups

- 2026-05-27: Check group workspace migration separately.
EOF

if memory_pack_path="$(bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$memory_root" \
  --platform feishu \
  --chat-id "oc/direct-memory" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$memory_user_workspace" \
  --user-workspace "$memory_user_workspace" \
  --conversation-dir "$memory_conversation_dir")" &&
  [ -f "$memory_pack_path" ] &&
  grep -Fq "Knot Memory Pack" "$memory_pack_path" &&
  grep -Fq "actor_user: direct-user" "$memory_pack_path" &&
  grep -Fq "write_targets:" "$memory_pack_path" &&
  grep -Fq "workspace/users/direct-user/memory/active.md" "$memory_pack_path" &&
  grep -Fq "Validate direct-chat memory pack" "$memory_pack_path" &&
  [ "$(mode_of "$memory_pack_path")" = "600" ]; then
  ok "knot-memory creates deterministic owner-only direct memory pack"
else
  fail "knot-memory did not create expected direct memory pack"
fi

if [ -f "$memory_pack_path" ]; then
  first_pack_hash="$(file_sha256 "$memory_pack_path")"
  if second_pack_path="$(bash "$ROOT/bin/knot-memory-pack.sh" pack \
    --root "$memory_root" \
    --platform feishu \
    --chat-id "oc/direct-memory" \
    --user-id "ou/direct-user" \
    --identity-key "feishu:user:direct" \
    --actor-user direct-user \
    --active-workspace "$memory_user_workspace" \
    --user-workspace "$memory_user_workspace" \
    --conversation-dir "$memory_conversation_dir")" &&
    [ "$second_pack_path" = "$memory_pack_path" ] &&
    [ "$(file_sha256 "$memory_pack_path")" = "$first_pack_hash" ]; then
    ok "knot-memory pack output is deterministic for unchanged inputs"
  else
    fail "knot-memory pack output changed for unchanged inputs"
  fi
else
  fail "knot-memory pack output is deterministic for unchanged inputs"
fi

if jq -e 'select(.event == "memory.pack.generated" and .status == "recorded")' "$memory_conversation_dir/events.jsonl" >/dev/null; then
  ok "knot-memory records compact memory.pack.generated audit event"
else
  fail "knot-memory did not record memory.pack.generated audit event"
fi

if env -u KNOT_CONVERSATION_DIR bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$memory_root" \
  --platform feishu \
  --chat-id "oc/direct-memory" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$memory_user_workspace" \
  --user-workspace "$memory_user_workspace" >/dev/null 2>&1; then
  fail "knot-memory allowed pack generation without conversation audit target"
else
  ok "knot-memory requires conversation audit target before generating pack"
fi

denied_hash="$(sha256_hex_pair feishu "oc/direct-denied")"
denied_conversation_dir="$memory_root/workspace/conversations/feishu/chat_${denied_hash:0:24}"
mkdir -p "$denied_conversation_dir"
if bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$memory_root" \
  --platform feishu \
  --chat-id "oc/direct-denied" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$memory_root/workspace/users/other-user" \
  --user-workspace "$memory_user_workspace" \
  --conversation-dir "$denied_conversation_dir" >/dev/null 2>&1; then
  fail "knot-memory allowed mismatched active/user workspace"
else
  ok "knot-memory fails closed on mismatched active/user workspace"
fi

if [ ! -e "$memory_root/workspace/users/other-user/.knot/memory-pack.md" ] &&
  jq -e 'select(.event == "memory.pack.denied" and .status == "denied" and .reason_code == "memory_workspace_mismatch")' "$denied_conversation_dir/events.jsonl" >/dev/null; then
  ok "knot-memory denial creates no pack and records audit event"
else
  fail "knot-memory denial did not preserve fail-closed audit behavior"
fi

ambiguous_root="$TMP_PARENT/memory-ambiguous-root"
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
if bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$ambiguous_root" \
  --platform feishu \
  --chat-id "oc/ambiguous" \
  --user-id "ou/ambiguous" \
  --identity-key "feishu:user:ambiguous" \
  --actor-user user-one \
  --active-workspace "$ambiguous_root/workspace/users/user-one" \
  --user-workspace "$ambiguous_root/workspace/users/user-one" \
  --conversation-dir "$ambiguous_conversation_dir" >/dev/null 2>&1; then
  fail "knot-memory allowed ambiguous permissions identity mapping"
else
  ok "knot-memory fails closed on ambiguous permissions identity mapping"
fi

if [ ! -e "$ambiguous_root/workspace/users/user-one/.knot/memory-pack.md" ] &&
  jq -e 'select(.event == "memory.pack.denied" and .status == "denied" and .reason_code == "memory_identity_ambiguous")' "$ambiguous_conversation_dir/events.jsonl" >/dev/null; then
  ok "knot-memory ambiguous identity denial creates no pack and records audit event"
else
  fail "knot-memory ambiguous identity denial did not preserve fail-closed audit behavior"
fi

mixed_ambiguous_root="$TMP_PARENT/memory-mixed-ambiguous-root"
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
if bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$mixed_ambiguous_root" \
  --platform feishu \
  --chat-id "oc/mixed" \
  --user-id "ou/mixed" \
  --identity-key "feishu:user:mixed" \
  --actor-user user-one \
  --active-workspace "$mixed_ambiguous_root/workspace/users/user-one" \
  --user-workspace "$mixed_ambiguous_root/workspace/users/user-one" \
  --conversation-dir "$mixed_conversation_dir" >/dev/null 2>&1; then
  fail "knot-memory allowed ambiguous platform user mapping when identity key was unique"
else
  ok "knot-memory fails closed when any provided identity dimension is ambiguous"
fi

if [ ! -e "$mixed_ambiguous_root/workspace/users/user-one/.knot/memory-pack.md" ] &&
  jq -e 'select(.event == "memory.pack.denied" and .status == "denied" and .reason_code == "memory_identity_ambiguous")' "$mixed_conversation_dir/events.jsonl" >/dev/null; then
  ok "knot-memory mixed ambiguity denial creates no pack and records audit event"
else
  fail "knot-memory mixed ambiguity denial did not preserve fail-closed audit behavior"
fi

missing_permissions_root="$TMP_PARENT/memory-missing-permissions-root"
mkdir -p "$missing_permissions_root/workspace/users" "$missing_permissions_root/workspace/conversations/feishu"
missing_permissions_hash="$(sha256_hex_pair feishu "oc/missing-permissions")"
missing_permissions_conversation_dir="$missing_permissions_root/workspace/conversations/feishu/chat_${missing_permissions_hash:0:24}"
mkdir -p "$missing_permissions_conversation_dir"
if bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$missing_permissions_root" \
  --platform feishu \
  --chat-id "oc/missing-permissions" \
  --user-id "ou/missing-permissions" \
  --identity-key "feishu:user:missing-permissions" \
  --actor-user missing-permissions \
  --active-workspace "$missing_permissions_root/workspace/users/missing-permissions" \
  --user-workspace "$missing_permissions_root/workspace/users/missing-permissions" \
  --conversation-dir "$missing_permissions_conversation_dir" >/dev/null 2>&1; then
  fail "knot-memory allowed memory pack without permissions source of truth"
else
  ok "knot-memory fails closed when permissions source of truth is missing"
fi

if [ ! -e "$missing_permissions_root/workspace/users/missing-permissions/.knot/memory-pack.md" ] &&
  jq -e 'select(.event == "memory.pack.denied" and .status == "denied" and .reason_code == "memory_identity_unresolved")' "$missing_permissions_conversation_dir/events.jsonl" >/dev/null; then
  ok "knot-memory missing permissions denial creates no pack and records audit event"
else
  fail "knot-memory missing permissions denial did not preserve fail-closed audit behavior"
fi

identity_only_root="$TMP_PARENT/memory-identity-only-root"
mkdir -p "$identity_only_root/workspace/admin" "$identity_only_root/workspace/users" "$identity_only_root/workspace/conversations/feishu"
cat > "$identity_only_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Identity User | identity-user | feishu |  |  | oc/identity-only | stable:identity:user | Identity User | member | session | smoke |
EOF
identity_only_hash="$(sha256_hex_pair feishu "oc/identity-only")"
identity_only_conversation_dir="$identity_only_root/workspace/conversations/feishu/chat_${identity_only_hash:0:24}"
mkdir -p "$identity_only_conversation_dir"
if identity_only_pack="$(bash "$ROOT/bin/knot-memory-pack.sh" pack \
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
  ok "knot-memory allows unique identity-key mapping without platform-user row"
else
  fail "knot-memory rejected unique identity-key mapping without platform-user row"
fi

symlink_root="$TMP_PARENT/memory-symlink-root"
symlink_outside="$TMP_PARENT/memory-symlink-outside"
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
if bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$symlink_root" \
  --platform feishu \
  --chat-id "oc/symlink" \
  --user-id "ou/symlink" \
  --identity-key "feishu:user:symlink" \
  --actor-user symlink-user \
  --active-workspace "$symlink_root/workspace/users/symlink-user" \
  --user-workspace "$symlink_root/workspace/users/symlink-user" \
  --conversation-dir "$symlink_conversation_dir" >/dev/null 2>&1; then
  fail "knot-memory allowed symlinked users root"
else
  ok "knot-memory fails closed before writing through symlinked users root"
fi

if [ ! -e "$symlink_outside/symlink-user" ] &&
  jq -e 'select(.event == "memory.pack.denied" and .status == "denied" and .reason_code == "symlink_denied")' "$symlink_conversation_dir/events.jsonl" >/dev/null; then
  ok "knot-memory symlink denial creates no outside files and records audit event"
else
  fail "knot-memory symlink denial wrote outside root or missed audit"
fi

real_root="$TMP_PARENT/memory-real-root"
root_link="$TMP_PARENT/memory-root-link"
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
if bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$root_link" \
  --platform feishu \
  --chat-id "oc/root-link" \
  --user-id "ou/root-link" \
  --identity-key "feishu:user:root-link" \
  --actor-user root-link-user \
  --active-workspace "$root_link/workspace/users/root-link-user" \
  --user-workspace "$root_link/workspace/users/root-link-user" \
  --conversation-dir "$root_link_conversation_dir" >/dev/null 2>&1; then
  fail "knot-memory allowed symlinked Knot root"
else
  ok "knot-memory rejects symlinked Knot root explicitly"
fi

if [ ! -e "$real_root/workspace/users/root-link-user/.knot/memory-pack.md" ] &&
  jq -e 'select(.event == "memory.pack.denied" and .status == "denied" and .reason_code == "symlink_denied")' "$root_link_conversation_dir/events.jsonl" >/dev/null; then
  ok "knot-memory symlink root denial creates no pack and records audit event"
else
  fail "knot-memory symlink root denial wrote pack or missed audit"
fi

chmod 644 "$memory_user_workspace/memory/active.md"
if bash "$ROOT/bin/knot-memory-pack.sh" pack \
  --root "$memory_root" \
  --platform feishu \
  --chat-id "oc/direct-memory" \
  --user-id "ou/direct-user" \
  --identity-key "feishu:user:direct" \
  --actor-user direct-user \
  --active-workspace "$memory_user_workspace" \
  --user-workspace "$memory_user_workspace" \
  --conversation-dir "$memory_conversation_dir" >/dev/null &&
  [ "$(mode_of "$memory_user_workspace/memory/active.md")" = "600" ]; then
  ok "knot-memory tightens existing memory file permissions"
else
  fail "knot-memory did not tighten existing memory file permissions"
fi

assert_event_schema "$memory_conversation_dir/events.jsonl"
assert_event_schema "$denied_conversation_dir/events.jsonl"
assert_event_schema "$ambiguous_conversation_dir/events.jsonl"
assert_event_schema "$mixed_conversation_dir/events.jsonl"
assert_event_schema "$missing_permissions_conversation_dir/events.jsonl"
assert_event_schema "$identity_only_conversation_dir/events.jsonl"
assert_event_schema "$symlink_conversation_dir/events.jsonl"
assert_event_schema "$root_link_conversation_dir/events.jsonl"
