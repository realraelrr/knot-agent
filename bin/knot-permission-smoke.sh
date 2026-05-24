#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEEP=0
FAILURES=0
TMP_PARENT=""

usage() {
  cat <<'EOF'
Usage: bash bin/knot-permission-smoke.sh [--root DIR] [--keep]

Runs deterministic permission-boundary checks against a temporary Knot
workspace. The script does not use live IM credentials or the real workspace.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || {
        printf 'ERROR --root requires a value\n' >&2
        exit 1
      }
      ROOT="$1"
      ;;
    --keep)
      KEEP=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

ROOT="$(cd "$ROOT" && pwd)"
TMP_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/knot-permission-smoke.XXXXXX")"
TEST_ROOT="$TMP_PARENT/root with spaces"

cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    printf 'Kept permission smoke workspace: %s\n' "$TMP_PARENT"
  else
    rm -rf "$TMP_PARENT"
  fi
}
trap cleanup EXIT

ok() {
  printf 'OK   %s\n' "$1"
}

fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

expect_ok() {
  local label="$1"
  shift
  local output

  if output="$("$@" 2>&1)"; then
    ok "$label"
  else
    fail "$label failed: $output"
  fi
}

expect_fail_contains() {
  local label="$1"
  local want="$2"
  shift 2
  local output

  if output="$("$@" 2>&1)"; then
    fail "$label unexpectedly passed: $output"
  elif printf '%s\n' "$output" | grep -Fq -- "$want"; then
    ok "$label"
  else
    fail "$label failed with unexpected output: $output"
  fi
}

workspace_export() {
  local key="$1"
  local data="$2"

  printf '%s\n' "$data" | sed -n "s/^export ${key}='\\(.*\\)'$/\\1/p" | sed "s/'\\\\''/'/g" | tail -1
}

mkdir -p \
  "$TEST_ROOT/workspace/admin" \
  "$TEST_ROOT/workspace/users/attacker-user/deliverables" \
  "$TEST_ROOT/workspace/users/victim-user/deliverables" \
  "$TEST_ROOT/workspace/groups/allowed-group/deliverables" \
  "$TEST_ROOT/workspace/groups/victim-group/deliverables" \
  "$TEST_ROOT/workspace/conversations/feishu/chat_000000000000000000000000" \
  "$TEST_ROOT/generated"

cat > "$TEST_ROOT/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Attacker User | attacker-user | feishu | ou_attacker | allowed-group | oc_allowed | feishu:user:attacker | Attacker | member | session | permission smoke |
| Victim User | victim-user | feishu | ou_victim | victim-group | oc_victim | feishu:user:victim | Victim | member | session | permission smoke |
EOF

printf 'attacker own deliverable\n' > "$TEST_ROOT/workspace/users/attacker-user/deliverables/own.txt"
printf 'victim private sentinel\n' > "$TEST_ROOT/workspace/users/victim-user/deliverables/private-sentinel.txt"
printf 'victim group sentinel\n' > "$TEST_ROOT/workspace/groups/victim-group/deliverables/group-private.txt"
printf 'conversation metadata\n' > "$TEST_ROOT/workspace/conversations/feishu/chat_000000000000000000000000/metadata.txt"
printf 'generated artifact\n' > "$TEST_ROOT/generated/report.txt"
printf 'external secret\n' > "$TMP_PARENT/outside-secret.txt"
ln -s "$TMP_PARENT/outside-secret.txt" "$TEST_ROOT/workspace/users/attacker-user/deliverables/outside-link.txt"

ATTACKER_CONTEXT=(
  --root "$TEST_ROOT"
  --platform feishu
  --chat-id oc_allowed
  --user-id ou_attacker
  --user-slug attacker-user
  --identity-key feishu:user:attacker
)

ATTACKER_GROUP_CONTEXT=(
  "${ATTACKER_CONTEXT[@]}"
  --group-slug allowed-group
)

VICTIM_GROUP_CONTEXT=(
  --root "$TEST_ROOT"
  --platform feishu
  --chat-id oc_victim
  --user-id ou_attacker
  --user-slug attacker-user
  --identity-key feishu:user:attacker
  --group-slug victim-group
)

WRONG_IDENTITY_CONTEXT=(
  --root "$TEST_ROOT"
  --platform feishu
  --chat-id oc_allowed
  --user-id ou_attacker
  --user-slug attacker-user
  --identity-key feishu:user:wrong
  --group-slug allowed-group
)

printf 'Knot permission smoke\n'
printf 'Test root: %s\n\n' "$TEST_ROOT"

expect_ok \
  "current user deliverable can be attached" \
  bash "$ROOT/bin/knot-attachment.sh" "${ATTACKER_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/users/attacker-user/deliverables/own.txt"

expect_fail_contains \
  "another user's deliverable cannot be attached" \
  "attachment must be inside the current user or group deliverables directory" \
  bash "$ROOT/bin/knot-attachment.sh" "${ATTACKER_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/users/victim-user/deliverables/private-sentinel.txt"

expect_fail_contains \
  "another user's workspace file cannot be delivered" \
  "source file belongs to another user workspace" \
  bash "$ROOT/bin/knot-deliver.sh" "${ATTACKER_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/users/victim-user/deliverables/private-sentinel.txt"

audit_exports="$(
  bash "$ROOT/bin/knot-workspace.sh" \
    --root "$TEST_ROOT" \
    --platform feishu \
    --chat-id oc_allowed \
    --user-id ou_attacker \
    --user-slug attacker-user \
    --identity-key feishu:user:attacker \
    --emit-conversation-initialized
)"
eval "$audit_exports"
AUDIT_CONVERSATION_DIR="$KNOT_CONVERSATION_DIR"

expect_fail_contains \
  "another user's workspace file delivery denial can be audited" \
  "source file belongs to another user workspace" \
  bash "$ROOT/bin/knot-deliver.sh" "${ATTACKER_CONTEXT[@]}" \
    --conversation-dir "$AUDIT_CONVERSATION_DIR" \
    --kind file \
    --path "$TEST_ROOT/workspace/users/victim-user/deliverables/private-sentinel.txt"

if jq -e 'select(.event == "delivery.denied" and .reason_code == "outside_deliverables")' "$AUDIT_CONVERSATION_DIR/events.jsonl" >/dev/null; then
  ok "audited cross-user delivery denial records a boundary event"
else
  fail "audited cross-user delivery denial did not record delivery.denied"
fi

expect_fail_contains \
  "conversation metadata cannot be delivered" \
  "cannot deliver files from workspace/conversations" \
  bash "$ROOT/bin/knot-deliver.sh" "${ATTACKER_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/conversations/feishu/chat_000000000000000000000000/metadata.txt"

expect_fail_contains \
  "conversation metadata cannot be attached" \
  "attachments cannot be sent from workspace/conversations" \
  bash "$ROOT/bin/knot-attachment.sh" "${ATTACKER_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/conversations/feishu/chat_000000000000000000000000/metadata.txt"

expect_fail_contains \
  "symlinked deliverable cannot escape the current user deliverables boundary" \
  "attachment must be inside the current user or group deliverables directory" \
  bash "$ROOT/bin/knot-attachment.sh" "${ATTACKER_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/users/attacker-user/deliverables/outside-link.txt"

expect_ok \
  "authorized group delivery can attach generated artifacts" \
  bash "$ROOT/bin/knot-deliver.sh" "${ATTACKER_GROUP_CONTEXT[@]}" \
    --kind file \
    --target group \
    --path "$TEST_ROOT/generated/report.txt"

expect_fail_contains \
  "unauthorized group target is rejected" \
  "group workspace is not authorized for this actor/context: victim-group" \
  bash "$ROOT/bin/knot-deliver.sh" "${VICTIM_GROUP_CONTEXT[@]}" \
    --kind file \
    --target group \
    --path "$TEST_ROOT/generated/report.txt"

expect_fail_contains \
  "wrong explicit identity key is rejected even when platform user id matches" \
  "group workspace is not authorized for this actor/context: allowed-group" \
  bash "$ROOT/bin/knot-deliver.sh" "${WRONG_IDENTITY_CONTEXT[@]}" \
    --kind file \
    --target group \
    --path "$TEST_ROOT/generated/report.txt"

expect_fail_contains \
  "another group's deliverable cannot be attached" \
  "attachment must be inside the current user or group deliverables directory" \
  bash "$ROOT/bin/knot-attachment.sh" "${ATTACKER_GROUP_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/groups/victim-group/deliverables/group-private.txt"

expect_fail_contains \
  "another group's workspace file cannot be delivered" \
  "source file belongs to another group workspace" \
  bash "$ROOT/bin/knot-deliver.sh" "${ATTACKER_GROUP_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/groups/victim-group/deliverables/group-private.txt"

resolver_exports="$(
  bash "$ROOT/bin/knot-workspace.sh" \
    --root "$TEST_ROOT" \
    --platform feishu \
    --chat-id oc_victim \
    --user-id ou_attacker \
    --identity-key feishu:user:attacker \
    --no-create
)"
resolver_group="$(workspace_export KNOT_GROUP_WORKSPACE "$resolver_exports")"
if [ -z "$resolver_group" ]; then
  ok "workspace resolver does not expose a group when chat matches but actor does not"
else
  fail "workspace resolver exposed unauthorized group: $resolver_group"
fi

wrong_identity_exports="$(
  bash "$ROOT/bin/knot-workspace.sh" \
    --root "$TEST_ROOT" \
    --platform feishu \
    --chat-id oc_allowed \
    --user-id ou_attacker \
    --identity-key feishu:user:wrong \
    --name Attacker \
    --no-create
)"
wrong_identity_user="$(workspace_export KNOT_ACTIVE_WORKSPACE "$wrong_identity_exports")"
wrong_identity_group="$(workspace_export KNOT_GROUP_WORKSPACE "$wrong_identity_exports")"
if [ "$wrong_identity_user" != "$TEST_ROOT/workspace/users/attacker-user" ] &&
  [ -z "$wrong_identity_group" ]; then
  ok "workspace resolver rejects mismatched explicit identity key before permission fallback"
else
  fail "workspace resolver resolved permissions row with mismatched explicit identity key"
fi

mv "$TEST_ROOT/workspace/users/attacker-user/deliverables" "$TEST_ROOT/workspace/users/attacker-user/deliverables.real"
mkdir -p "$TMP_PARENT/symlinked-deliverables"
ln -s "$TMP_PARENT/symlinked-deliverables" "$TEST_ROOT/workspace/users/attacker-user/deliverables"
printf 'symlinked output\n' > "$TMP_PARENT/symlinked-deliverables/own.txt"

expect_fail_contains \
  "symlinked current deliverables directory is rejected" \
  "current user workspace and deliverables must not be symlinks" \
  bash "$ROOT/bin/knot-attachment.sh" "${ATTACKER_CONTEXT[@]}" \
    --kind file \
    --path "$TEST_ROOT/workspace/users/attacker-user/deliverables/own.txt"

printf '\nDone.\n'
if [ "$FAILURES" -gt 0 ]; then
  printf 'FAILED %s permission smoke check(s).\n' "$FAILURES"
  exit 1
fi
