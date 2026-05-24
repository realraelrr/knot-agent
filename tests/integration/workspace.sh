# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

TMP_PARENT="$(mktemp -d)"
tmp_root="$TMP_PARENT/root with spaces"
mkdir -p "$tmp_root"

workspace_exports="$(bash "$ROOT/bin/knot-workspace.sh" \
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
chat_hash="$(sha256_hex_pair feishu "oc/test group")"
expected_conversation_segment="chat_${chat_hash:0:24}"

if [ -d "$user_workspace/deliverables" ] &&
  [ -d "$group_workspace/deliverables" ] &&
  [ -f "$conversation_dir/metadata.tsv" ] &&
  grep -Fq $'actor_user\texample-user' "$conversation_dir/metadata.tsv"; then
  ok "knot-workspace creates user/group workspaces and conversation metadata"
else
  fail "knot-workspace did not create expected user/group/conversation state"
fi

if [ "$(basename "$conversation_dir")" = "$expected_conversation_segment" ] &&
  printf '%s\n' "$conversation_dir" | grep -Fq "/workspace/conversations/feishu/chat_" &&
  ! printf '%s\n' "$conversation_dir" | grep -Fq "oc_test_group"; then
  ok "knot-workspace uses opaque conversation directory segments"
else
  fail "knot-workspace conversation directory exposed raw or sanitized chat id: $conversation_dir"
fi

event_log="$conversation_dir/events.jsonl"
if [ ! -e "$event_log" ]; then
  ok "workspace resolution without explicit audit flag creates no event log"
else
  fail "workspace resolution created event log without explicit audit flag"
fi

audit_chat_id="oc/audit group"
audit_hash="$(sha256_hex_pair feishu "$audit_chat_id")"
audit_conversation_dir="$tmp_root/workspace/conversations/feishu/chat_${audit_hash:0:24}"
if audit_exports="$(bash "$ROOT/bin/knot-workspace.sh" \
  --root "$tmp_root" \
  --platform feishu \
  --chat-id "$audit_chat_id" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --identity-key "feishu:user:ou-test" \
  --emit-conversation-initialized)" &&
  eval "$audit_exports" &&
  [ "$KNOT_CONVERSATION_DIR" = "$audit_conversation_dir" ] &&
  [ -f "$audit_conversation_dir/events.jsonl" ] &&
  jq -e 'select(.event == "conversation.initialized" and .status == "allowed")' "$audit_conversation_dir/events.jsonl" >/dev/null &&
  ! grep -Fq "$audit_chat_id" "$audit_conversation_dir/events.jsonl" &&
  ! grep -Fq "ou/test user" "$audit_conversation_dir/events.jsonl" &&
  ! grep -Fq "feishu:user:ou-test" "$audit_conversation_dir/events.jsonl"; then
  ok "knot-workspace explicit audit writes hashed conversation.initialized event"
else
  fail "knot-workspace explicit audit did not write expected conversation.initialized event"
fi

before_repeat_init_count="$(wc -l < "$audit_conversation_dir/events.jsonl" | tr -d '[:space:]')"
if bash "$ROOT/bin/knot-workspace.sh" \
  --root "$tmp_root" \
  --platform feishu \
  --chat-id "$audit_chat_id" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --identity-key "feishu:user:ou-test" \
  --emit-conversation-initialized >/dev/null &&
  [ "$(wc -l < "$audit_conversation_dir/events.jsonl" | tr -d '[:space:]')" = "$before_repeat_init_count" ]; then
  ok "knot-workspace does not duplicate conversation.initialized events"
else
  fail "knot-workspace duplicated conversation.initialized event"
fi

assert_event_schema "$audit_conversation_dir/events.jsonl"

if bash "$ROOT/bin/knot-audit.sh" record \
  --root "$tmp_root" \
  --conversation-dir "$audit_conversation_dir" \
  --event conversation.initialized \
  --platform feishu \
  --chat-id-hash "sha256:0000000000000000000000000000000000000000000000000000000000000000" \
  --status allowed >/dev/null 2>&1; then
  fail "knot-audit allowed chat hash mismatch"
else
  ok "knot-audit rejects chat hash mismatch"
fi

wrong_platform_dir="$tmp_root/workspace/conversations/dingtalk/chat_${audit_hash:0:24}"
mkdir -p "$wrong_platform_dir"
if bash "$ROOT/bin/knot-audit.sh" record \
  --root "$tmp_root" \
  --conversation-dir "$wrong_platform_dir" \
  --event conversation.initialized \
  --platform feishu \
  --chat-id-hash "sha256:$audit_hash" \
  --status allowed >/dev/null 2>&1; then
  fail "knot-audit allowed parent platform mismatch"
else
  ok "knot-audit rejects parent platform mismatch"
fi

eval "$workspace_exports"

mkdir -p "$tmp_root/workspace/admin"
cat > "$tmp_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Example User | example-user | feishu | ou/test user | example-group | oc/test group | feishu:user:ou-test | Smoke Test | member | session | smoke |
| Jane Example | jane-example | feishu | ou/jane | product-room | oc/product | feishu:user:ou/jane | Jane Example | member | session | smoke |
EOF

if resolved_exports="$(bash "$ROOT/bin/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/jane" --identity-key "feishu:user:ou/jane" --name "Ignored Name" --group-name "Ignored Group")" &&
  eval "$resolved_exports" &&
  [ "$KNOT_ACTIVE_WORKSPACE" = "$tmp_root/workspace/users/jane-example" ] &&
  [ "$KNOT_GROUP_WORKSPACE" = "$tmp_root/workspace/groups/product-room" ]; then
  ok "knot-workspace resolves user/group slugs from permissions table"
else
  fail "knot-workspace did not resolve permissions table slugs"
fi

if resolved_exports="$(bash "$ROOT/bin/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/bob" --identity-key "feishu:user:ou/bob" --name "Bob Example" --group-name "Ignored Group")" &&
  eval "$resolved_exports" &&
  [ -z "$KNOT_GROUP_WORKSPACE" ]; then
  ok "knot-workspace requires actor match before exposing permissions group"
else
  fail "knot-workspace exposed permissions group to unmatched actor"
fi

if resolved_exports="$(bash "$ROOT/bin/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/jane" --identity-key "feishu:user:wrong" --name "Jane Example" --group-name "Ignored Group")" &&
  eval "$resolved_exports" &&
  [ "$KNOT_ACTIVE_WORKSPACE" != "$tmp_root/workspace/users/jane-example" ] &&
  [ -z "$KNOT_GROUP_WORKSPACE" ]; then
  ok "knot-workspace rejects mismatched explicit identity key before permission fallback"
else
  fail "knot-workspace resolved permissions row with mismatched explicit identity key"
fi

if bash "$ROOT/bin/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id $'oc/bad\tchat' --user-id "ou/test user" --user-slug "bad-meta" >/dev/null 2>&1; then
  fail "knot-workspace allowed tab in chat metadata"
else
  ok "knot-workspace rejects tabs in chat metadata"
fi
eval "$workspace_exports"
