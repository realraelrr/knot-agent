#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"
PLATFORM="${KNOT_PLATFORM:-}"
CHAT_ID="${KNOT_CHAT_ID:-}"
USER_ID="${KNOT_PLATFORM_USER_ID:-}"
USER_SLUG="${KNOT_ACTOR_USER:-}"
GROUP_SLUG="${KNOT_SOURCE_GROUP:-}"
IDENTITY_KEY="${KNOT_IDENTITY_KEY:-}"
CONVERSATION_DIR="${KNOT_CONVERSATION_DIR:-}"
KIND=""
FILE_PATH=""
# Set by this script and read by parser helpers from lib/knot/core.sh.
# shellcheck disable=SC2034
EXPLICIT_CONTEXT=0
# shellcheck disable=SC2034
EXPLICIT_IDENTITY_KEY=0
# shellcheck disable=SC2034
EXPLICIT_GROUP_SLUG=0

usage() {
  cat <<'EOF'
Usage: bash bin/knot-attachment.sh --platform NAME --user-id ID --user-slug SLUG --kind image|file --path FILE [options]

Options:
  --root DIR          Knot root. Defaults to the parent of this script.
  --chat-id ID        Source chat id for conversation context.
  --conversation-dir DIR
                      Conversation audit directory from Knot workspace routing.
  --group-slug SLUG   Current group workspace slug for group chats.
  --help, -h          Show this help.

Validates that FILE exists under the current user deliverables directory, or
under the current group deliverables directory when --group-slug is provided,
then prints a cc-connect attachment block.
EOF
}

message_for_reason_code() {
  case "$1" in
    unauthorized_group)
      printf 'group workspace is not authorized for this actor/context: %s\n' "$GROUP_SLUG"
      ;;
    conversation_source_denied)
      printf 'attachments cannot be sent from workspace/conversations\n'
      ;;
    outside_deliverables)
      printf 'attachment must be inside the current user or group deliverables directory\n'
      ;;
    invalid_resource)
      printf 'file not found: %s\n' "$FILE_PATH"
      ;;
    *)
      printf 'attachment denied\n'
      ;;
  esac
}

deny_delivery() {
  local reason_code="$1"
  knot_audit_deny_delivery "$reason_code" "$KIND" "$FILE_PATH" "$(message_for_reason_code "$reason_code")"
}

deny_delivery_with_message() {
  local reason_code="$1"
  local message="$2"

  knot_audit_deny_delivery "$reason_code" "$KIND" "$FILE_PATH" "$message"
}

deny_group_access() {
  knot_audit_deny_group_access "$(message_for_reason_code unauthorized_group)"
}

while [ "$#" -gt 0 ]; do
  if parse_knot_context_arg "$@"; then
    shift "$KNOT_ARG_CONSUMED"
    continue
  fi

  case "$1" in
    --kind)
      shift
      [ "$#" -gt 0 ] || die "--kind requires a value"
      KIND="$1"
      ;;
    --path)
      shift
      [ "$#" -gt 0 ] || die "--path requires a value"
      FILE_PATH="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

require_knot_context
[ -n "$KIND" ] || die "--kind is required"
[ -n "$FILE_PATH" ] || die "--path is required"
clear_implicit_identity_key

case "$KIND" in
  image|file)
    ;;
  *)
    die "--kind must be image or file"
    ;;
esac

[ -f "$FILE_PATH" ] || deny_delivery invalid_resource
ROOT="$(cd "$ROOT" && pwd)"
if [ -n "$GROUP_SLUG" ] && ! permissions_group_authorized "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG"; then
  deny_group_access
fi
WORKSPACE_ARGS=(--root "$ROOT" --platform "$PLATFORM" --user-id "$USER_ID" --user-slug "$USER_SLUG" --no-create)
[ -z "$CHAT_ID" ] || WORKSPACE_ARGS+=(--chat-id "$CHAT_ID")
[ -z "$GROUP_SLUG" ] || WORKSPACE_ARGS+=(--group-slug "$GROUP_SLUG")
WORKSPACE_EXPORTS="$(bash "$SCRIPT_DIR/knot-workspace.sh" "${WORKSPACE_ARGS[@]}")"
USER_WORKSPACE="$(workspace_export KNOT_USER_WORKSPACE "$WORKSPACE_EXPORTS")"
GROUP_WORKSPACE="$(workspace_export KNOT_GROUP_WORKSPACE "$WORKSPACE_EXPORTS")"

if [ -L "$USER_WORKSPACE" ] || [ -L "$USER_WORKSPACE/deliverables" ]; then
  deny_delivery_with_message symlink_denied "current user workspace and deliverables must not be symlinks"
fi

if [ -n "$GROUP_WORKSPACE" ] && { [ -L "$GROUP_WORKSPACE" ] || [ -L "$GROUP_WORKSPACE/deliverables" ]; }; then
  deny_delivery_with_message symlink_denied "current group workspace and deliverables must not be symlinks"
fi

USER_DELIVERABLES_DIR="$(resolve_path "$USER_WORKSPACE/deliverables")" || die "cannot resolve user deliverables directory"
GROUP_DELIVERABLES_DIR=""
if [ -n "$GROUP_WORKSPACE" ]; then
  GROUP_DELIVERABLES_DIR="$(resolve_path "$GROUP_WORKSPACE/deliverables")" || die "cannot resolve group deliverables directory"
fi

ABS_FILE="$(resolve_path "$FILE_PATH")" || die "cannot resolve file path: $FILE_PATH"
CONVERSATIONS_DIR="$(resolve_path "$ROOT/workspace/conversations" 2>/dev/null || true)"

if [ -n "$CONVERSATIONS_DIR" ]; then
  case "$ABS_FILE" in
    "$CONVERSATIONS_DIR"/*)
      deny_delivery conversation_source_denied
      ;;
  esac
fi

if path_is_under "$ABS_FILE" "$USER_DELIVERABLES_DIR"; then
  :
elif [ -n "$GROUP_DELIVERABLES_DIR" ] && path_is_under "$ABS_FILE" "$GROUP_DELIVERABLES_DIR"; then
  knot_audit_record group.access.allowed allowed || true
else
  deny_delivery outside_deliverables
fi

knot_audit_record delivery.verified allowed "" "$KIND" "$ABS_FILE" || true

printf '```cc-connect-attachments\n'
printf '%s: %s\n' "$KIND" "$ABS_FILE"
printf '```\n'
