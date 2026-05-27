# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

clear_knot_env

# Depends on workspace.sh creating the shared smoke workspace.
printf 'ok\n' > "$user_workspace/deliverables/result.txt"
if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/direct delivery" --user-id "ou/test user" --user-slug "example-user" --kind file --path "$user_workspace/deliverables/result.txt" >/dev/null; then
  ok "knot-attachment allows current user deliverable"
else
  fail "knot-attachment rejected current user deliverable"
fi

if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/result.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed user deliverable in group scope"
else
  ok "knot-attachment rejects user deliverable in group scope"
fi

if bash "$ROOT/bin/knot-attachment.sh" \
  --root "$tmp_root" \
  --conversation-dir "$audit_conversation_dir" \
  --platform feishu \
  --chat-id "$audit_chat_id" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --identity-key "feishu:user:ou-test" \
  --kind file \
  --path "$user_workspace/deliverables/result.txt" >/dev/null &&
  jq -e 'select(.event == "delivery.verified" and .resource_kind == "file" and (.resource_sha256 | length == 64))' "$audit_conversation_dir/events.jsonl" >/dev/null &&
  ! grep -Fq "$audit_chat_id" "$audit_conversation_dir/events.jsonl" &&
  ! grep -Fq "ou/test user" "$audit_conversation_dir/events.jsonl" &&
  ! grep -Fq "feishu:user:ou-test" "$audit_conversation_dir/events.jsonl"; then
  ok "knot-attachment writes compact hashed delivery.verified event"
else
  fail "knot-attachment did not write expected delivery.verified audit event"
fi

printf 'group\n' > "$group_workspace/deliverables/group.txt"
if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$group_workspace/deliverables/group.txt" >/dev/null; then
  ok "knot-attachment allows current group deliverable"
else
  fail "knot-attachment rejected current group deliverable"
fi

if bash "$ROOT/bin/knot-attachment.sh" \
  --root "$tmp_root" \
  --conversation-dir "$conversation_dir" \
  --platform feishu \
  --chat-id "oc/test group" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --group-slug "example-group" \
  --kind file \
  --path "$group_workspace/deliverables/group.txt" >/dev/null &&
  [ -f "$event_log" ] &&
  jq -e 'select(.event == "group.access.allowed" and .status == "allowed")' "$event_log" >/dev/null &&
  jq -e 'select(.event == "delivery.verified" and .resource_kind == "file")' "$event_log" >/dev/null; then
  ok "knot-attachment audits current group deliverable access"
else
  fail "knot-attachment did not audit current group deliverable access"
fi

mkdir -p "$actor_workspace/generated" "$user_workspace/work" "$tmp_root/runtime" "$tmp_root/.git"
printf 'generated\n' > "$actor_workspace/generated/image.png"
if deliver_output="$(bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$actor_workspace/generated/image.png")"; then
  expected_deliverable="$(resolve_path "$group_workspace/deliverables/image.png")"
  if [ -f "$group_workspace/deliverables/image.png" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq '```cc-connect-attachments' &&
    printf '%s\n' "$deliver_output" | grep -Fq "image: $expected_deliverable"; then
    ok "knot-deliver defaults group scope delivery to group deliverables"
  else
    fail "knot-deliver did not default group scope delivery to group deliverables"
  fi
else
  fail "knot-deliver rejected generated artifact"
fi

if deliver_output="$(bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$actor_workspace/generated/image.png" --target group --output-name "shared.png")"; then
  if [ -f "$group_workspace/deliverables/shared.png" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/shared.png")"; then
    ok "knot-deliver can target current group deliverables explicitly"
  else
    fail "knot-deliver did not copy generated artifact to group deliverables"
  fi
else
  fail "knot-deliver rejected explicit group delivery"
fi

if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$actor_workspace/.knot/current-context.sh" >/dev/null 2>&1; then
  fail "knot-deliver allowed actor lane internal context source"
else
  ok "knot-deliver rejects actor lane internal context source"
fi

mkdir -p "$actor_workspace/.state"
printf 'state\n' > "$actor_workspace/.state/internal.txt"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$actor_workspace/.state/internal.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed actor lane internal state source"
else
  ok "knot-deliver rejects actor lane internal state source"
fi

printf 'env-generated\n' > "$actor_workspace/generated/env.png"
if deliver_output="$(env \
  KNOT_ROOT="$tmp_root" \
  KNOT_PLATFORM=feishu \
  KNOT_PLATFORM_USER_ID="ou/test user" \
  KNOT_ACTOR_USER=example-user \
  KNOT_SOURCE_GROUP=example-group \
  KNOT_CHAT_ID="oc/test group" \
  KNOT_IDENTITY_KEY="feishu:user:ou-test" \
  bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --kind image --path "$actor_workspace/generated/env.png" --output-name "env-shared.png")"; then
  if [ -f "$group_workspace/deliverables/env-shared.png" ] &&
    printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/env-shared.png")"; then
    ok "knot-deliver preserves env group context when CLI overrides root"
  else
    fail "knot-deliver env-context delivery did not create expected group deliverable"
  fi
else
  fail "knot-deliver lost env group context when CLI overrode root"
fi

if attach_output="$(env \
  KNOT_ROOT="$tmp_root" \
  KNOT_PLATFORM=feishu \
  KNOT_PLATFORM_USER_ID="ou/test user" \
  KNOT_ACTOR_USER=example-user \
  KNOT_SOURCE_GROUP=example-group \
  KNOT_CHAT_ID="oc/test group" \
  KNOT_IDENTITY_KEY="feishu:user:ou-test" \
  bash "$ROOT/bin/knot-attachment.sh" --kind image --path "$group_workspace/deliverables/env-shared.png")" &&
  printf '%s\n' "$attach_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/env-shared.png")"; then
  ok "knot-attachment reads current context from KNOT_* environment"
else
  fail "knot-attachment did not accept KNOT_* environment context"
fi

if unauthorized_output="$(bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "unauthorized-group" --kind image --path "$actor_workspace/generated/image.png" --target group 2>&1)"; then
  fail "knot-deliver allowed unauthorized explicit group delivery"
elif printf '%s\n' "$unauthorized_output" | grep -Fq "not authorized"; then
  ok "knot-deliver rejects unauthorized explicit group delivery"
else
  fail "knot-deliver unauthorized group rejection had wrong error: $unauthorized_output"
fi

if unauthorized_output="$(bash "$ROOT/bin/knot-deliver.sh" \
  --root "$tmp_root" \
  --conversation-dir "$conversation_dir" \
  --platform feishu \
  --chat-id "oc/test group" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --group-slug "unauthorized-group" \
  --kind image \
  --path "$actor_workspace/generated/image.png" \
  --target group 2>&1)"; then
  fail "knot-deliver allowed audited unauthorized explicit group delivery"
elif jq -e 'select(.event == "group.access.denied" and .reason_code == "unauthorized_group")' "$event_log" >/dev/null; then
  ok "knot-deliver audits unauthorized group delivery denial"
else
  fail "knot-deliver did not audit unauthorized group delivery denial: $unauthorized_output"
fi

if unauthorized_output="$(bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --identity-key "feishu:user:wrong" --kind image --path "$actor_workspace/generated/image.png" --target group 2>&1)"; then
  fail "knot-deliver allowed group delivery with mismatched identity key"
elif printf '%s\n' "$unauthorized_output" | grep -Fq "not authorized"; then
  ok "knot-deliver rejects mismatched identity key for group delivery"
else
  fail "knot-deliver identity mismatch rejection had wrong error: $unauthorized_output"
fi

if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/result.txt" --target group --output-name "result-shared.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed user workspace source in group scope"
else
  ok "knot-deliver rejects user workspace source in group scope"
fi

printf 'direct-generated\n' > "$user_workspace/work/image.png"
if stale_context_output="$(env \
  KNOT_ROOT="$tmp_root" \
  KNOT_PLATFORM=feishu \
  KNOT_PLATFORM_USER_ID="ou/test user" \
  KNOT_ACTOR_USER=example-user \
  KNOT_SOURCE_GROUP=example-group \
  KNOT_CHAT_ID="oc/test group" \
  KNOT_IDENTITY_KEY="feishu:user:ou-test" \
  bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/direct delivery" --user-id "ou/test user" --user-slug "example-user" --kind image --path "$user_workspace/work/image.png" --output-name "stale-env-group.png" 2>&1)"; then
  fail "knot-deliver allowed stale env group with explicit direct context"
elif printf '%s\n' "$stale_context_output" | grep -Fq "not authorized"; then
  ok "knot-deliver fails closed for stale env group with explicit direct context"
else
  fail "knot-deliver stale env group rejection had wrong error: $stale_context_output"
fi

ln -s "$tmp_root/escaped-delivery.png" "$user_workspace/deliverables/symlink.png"
if deliver_output="$(bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/direct delivery" --user-id "ou/test user" --user-slug "example-user" --kind image --path "$user_workspace/work/image.png" --output-name "symlink.png")"; then
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
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_user_workspace/deliverables/private.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed artifact from another user workspace"
else
  ok "knot-deliver rejects artifact from another user workspace"
fi

other_group_workspace="$tmp_root/workspace/groups/other-group"
mkdir -p "$other_group_workspace/deliverables"
printf 'group-private\n' > "$other_group_workspace/deliverables/private.txt"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_group_workspace/deliverables/private.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed artifact from another group workspace"
else
  ok "knot-deliver rejects artifact from another group workspace"
fi

printf 'audit\n' > "$conversation_dir/audit.txt"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$conversation_dir/audit.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed artifact from conversations metadata"
else
  ok "knot-deliver rejects artifact from conversations metadata"
fi
if bash "$ROOT/bin/knot-deliver.sh" \
  --root "$tmp_root" \
  --conversation-dir "$conversation_dir" \
  --platform feishu \
  --chat-id "oc/test group" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --group-slug "example-group" \
  --kind file \
  --path "$conversation_dir/audit.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed audited artifact from conversations metadata"
elif jq -e 'select(.event == "delivery.denied" and .reason_code == "conversation_source_denied")' "$event_log" >/dev/null; then
  ok "knot-deliver audits conversation metadata delivery denial"
else
  fail "knot-deliver did not audit conversation metadata delivery denial"
fi
if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$conversation_dir/audit.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed artifact from conversations metadata"
else
  ok "knot-attachment rejects artifact from conversations metadata"
fi
if bash "$ROOT/bin/knot-attachment.sh" \
  --root "$tmp_root" \
  --conversation-dir "$conversation_dir" \
  --platform feishu \
  --chat-id "oc/test group" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --group-slug "example-group" \
  --kind file \
  --path "$conversation_dir/audit.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed audited artifact from conversations metadata"
elif jq -e 'select(.event == "delivery.denied" and .reason_code == "conversation_source_denied")' "$event_log" >/dev/null; then
  ok "knot-attachment audits conversation metadata attachment denial"
else
  fail "knot-attachment did not audit conversation metadata attachment denial"
fi

printf 'runtime-secret\n' > "$tmp_root/runtime/.env"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/direct delivery" --user-id "ou/test user" --user-slug "example-user" --kind file --path "$tmp_root/runtime/.env" >/dev/null 2>&1; then
  fail "knot-deliver allowed runtime secret source"
else
  ok "knot-deliver rejects runtime secret source"
fi

if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/direct delivery" --user-id "ou/test user" --user-slug "example-user" --kind file --path "$tmp_root/workspace/admin/permissions.md" >/dev/null 2>&1; then
  fail "knot-deliver allowed admin metadata source"
else
  ok "knot-deliver rejects admin metadata source"
fi

printf 'git-private\n' > "$tmp_root/.git/config"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/direct delivery" --user-id "ou/test user" --user-slug "example-user" --kind file --path "$tmp_root/.git/config" >/dev/null 2>&1; then
  fail "knot-deliver allowed git metadata source"
else
  ok "knot-deliver rejects git metadata source"
fi

invalid_audit_dir="$tmp_root/workspace/conversations/feishu/chat_000000000000000000000000"
mkdir -p "$invalid_audit_dir"
if invalid_audit_output="$(bash "$ROOT/bin/knot-attachment.sh" \
  --root "$tmp_root" \
  --conversation-dir "$invalid_audit_dir" \
  --platform feishu \
  --chat-id "oc/test group" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --group-slug "example-group" \
  --kind file \
  --path "$group_workspace/deliverables/group.txt" 2>&1)" ||
  printf '%s\n' "$invalid_audit_output" | grep -Fq '```cc-connect-attachments'; then
  fail "knot-attachment allowed output when explicit audit target was invalid"
else
  ok "knot-attachment blocks output when explicit audit target is invalid"
fi

if invalid_audit_output="$(bash "$ROOT/bin/knot-deliver.sh" \
  --root "$tmp_root" \
  --conversation-dir "$invalid_audit_dir" \
  --platform feishu \
  --chat-id "oc/test group" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --group-slug "example-group" \
  --kind file \
  --path "$actor_workspace/generated/image.png" \
  --output-name "invalid-audit-copy.txt" 2>&1)" ||
  printf '%s\n' "$invalid_audit_output" | grep -Fq '```cc-connect-attachments'; then
  fail "knot-deliver allowed output when explicit audit target was invalid"
elif [ -e "$group_workspace/deliverables/invalid-audit-copy.txt" ]; then
  fail "knot-deliver left deliverable file when explicit audit target was invalid"
else
  ok "knot-deliver blocks output when explicit audit target is invalid"
fi

if invalid_audit_output="$(bash "$ROOT/bin/knot-deliver.sh" \
  --root "$tmp_root" \
  --conversation-dir "$invalid_audit_dir" \
  --platform feishu \
  --chat-id "oc/direct delivery" \
  --user-id "ou/test user" \
  --user-slug "example-user" \
  --kind file \
  --path "$tmp_root/runtime/.env" 2>&1)"; then
  fail "knot-deliver allowed denied source when explicit audit target was invalid"
elif printf '%s\n' "$invalid_audit_output" | grep -Fq "audit event could not be recorded"; then
  ok "knot-deliver reports failed denial audit before returning"
else
  fail "knot-deliver did not report failed denial audit: $invalid_audit_output"
fi

printf 'external\n' > "$user_workspace/work/external.txt"
ln -s "$user_workspace/work/external.txt" "$other_user_workspace/deliverables/external-link.txt"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_user_workspace/deliverables/external-link.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed symlink path from another user workspace"
else
  ok "knot-deliver rejects symlink path from another user workspace"
fi

printf 'outside\n' > "$tmp_root/outside.txt"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/direct delivery" --user-id "ou/test user" --user-slug "example-user" --kind file --path "$tmp_root/outside.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed unapproved root-level source"
else
  ok "knot-deliver rejects unapproved root-level source"
fi
if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$tmp_root/outside.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed file outside current user/group workspaces"
else
  ok "knot-attachment rejects file outside current user/group workspaces"
fi

assert_event_schema "$event_log"
assert_event_schema "$audit_conversation_dir/events.jsonl"

ln -s "$tmp_root/outside.txt" "$user_workspace/deliverables/leak.txt"
if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/leak.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed symlink escaping current user workspace"
else
  ok "knot-attachment rejects symlink escaping current user workspace"
fi

mv "$user_workspace/deliverables" "$user_workspace/deliverables-real"
ln -s "$user_workspace/deliverables-real" "$user_workspace/deliverables"
if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables-real/result.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed symlinked user deliverables directory"
else
  ok "knot-attachment rejects symlinked user deliverables directory"
fi
rm "$user_workspace/deliverables"
mv "$user_workspace/deliverables-real" "$user_workspace/deliverables"

ln -s "$user_workspace" "$tmp_root/workspace/users/alias-user"
if bash "$ROOT/bin/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "alias-user" --kind file --path "$user_workspace/deliverables/result.txt" >/dev/null 2>&1; then
  fail "knot-attachment allowed symlinked user workspace slug"
else
  ok "knot-attachment rejects symlinked user workspace slug"
fi
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "alias-user" --kind file --path "$user_workspace/work/external.txt" >/dev/null 2>&1; then
  fail "knot-deliver allowed symlinked user workspace slug"
else
  ok "knot-deliver rejects symlinked user workspace slug"
fi

ln -s "$group_workspace" "$tmp_root/workspace/groups/alias-group"
if bash "$ROOT/bin/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "alias-group" --target group --kind file --path "$actor_workspace/generated/image.png" >/dev/null 2>&1; then
  fail "knot-deliver allowed symlinked group workspace slug"
else
  ok "knot-deliver rejects symlinked group workspace slug"
fi
