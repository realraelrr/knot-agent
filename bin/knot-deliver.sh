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
NAME="${KNOT_ACTOR_NAME:-}"
GROUP_NAME="${KNOT_SOURCE_GROUP_NAME:-}"
KIND=""
SOURCE_PATH=""
OUTPUT_NAME=""
TARGET="user"
# Set by this script and read by parser helpers from lib/knot/core.sh.
# shellcheck disable=SC2034
EXPLICIT_CONTEXT=0
# shellcheck disable=SC2034
EXPLICIT_IDENTITY_KEY=0
# shellcheck disable=SC2034
EXPLICIT_GROUP_SLUG=0
# shellcheck disable=SC2034
KNOT_PARSE_NAMES=1

usage() {
  cat <<'EOF'
Usage: bash bin/knot-deliver.sh --platform NAME --user-id ID --user-slug SLUG --kind image|file --path FILE [options]

Options:
  --root DIR           Knot root. Defaults to the parent of this script.
  --chat-id ID         Source chat id for conversation context.
  --conversation-dir DIR
                       Conversation audit directory from Knot workspace routing.
  --group-slug SLUG    Current group workspace slug for group chats.
  --identity-key KEY   Stable identity/context key from the IM glue layer.
  --name NAME          Human display name to record in metadata.
  --group-name NAME    Human group display name to record in metadata.
  --target user|group  Deliver into the current user workspace or group workspace.
  --output-name NAME   File name to use under the deliverables directory.
  --help, -h           Show this help.

Copies FILE into the selected current deliverables directory when needed,
validates the boundary, then prints a cc-connect attachment block.
EOF
}

message_for_reason_code() {
  case "$1" in
    unauthorized_group)
      printf 'group workspace is not authorized for this actor/context: %s\n' "$GROUP_SLUG"
      ;;
    conversation_source_denied)
      printf 'cannot deliver files from workspace/conversations\n'
      ;;
    outside_deliverables)
      printf 'source file belongs outside the current user or group workspace\n'
      ;;
    invalid_resource)
      printf 'file not found: %s\n' "$SOURCE_PATH"
      ;;
    *)
      printf 'delivery denied\n'
      ;;
  esac
}

deny_delivery() {
  local reason_code="$1"
  knot_audit_deny_delivery "$reason_code" "$KIND" "$SOURCE_PATH" "$(message_for_reason_code "$reason_code")"
}

deny_group_access() {
  knot_audit_deny_group_access "$(message_for_reason_code unauthorized_group)"
}

deny_delivery_with_message() {
  local reason_code="$1"
  local message="$2"

  knot_audit_deny_delivery "$reason_code" "$KIND" "$SOURCE_PATH" "$message"
}

reject_non_current_workspace_source() {
  local path="$1"

  [ -n "$path" ] || return 0

  if [ -n "$CONVERSATIONS_DIR" ] && path_is_under "$path" "$CONVERSATIONS_DIR"; then
    deny_delivery conversation_source_denied
  fi

  if path_is_under "$path" "$USERS_DIR" && ! path_is_under "$path" "$USER_REAL"; then
    deny_delivery_with_message outside_deliverables "source file belongs to another user workspace"
  fi

  if path_is_under "$path" "$GROUPS_DIR"; then
    if [ -z "$GROUP_REAL" ] || ! path_is_under "$path" "$GROUP_REAL"; then
      deny_delivery_with_message outside_deliverables "source file belongs to another group workspace"
    fi
  fi
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
      SOURCE_PATH="$1"
      ;;
    --target)
      shift
      [ "$#" -gt 0 ] || die "--target requires a value"
      TARGET="$1"
      ;;
    --output-name)
      shift
      [ "$#" -gt 0 ] || die "--output-name requires a value"
      OUTPUT_NAME="$1"
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
[ -n "$SOURCE_PATH" ] || die "--path is required"
clear_implicit_identity_key

case "$KIND" in
  image|file)
    ;;
  *)
    die "--kind must be image or file"
    ;;
esac

case "$TARGET" in
  user|group)
    ;;
  *)
    die "--target must be user or group"
    ;;
esac

[ "$TARGET" != "group" ] || [ -n "$GROUP_SLUG" ] || die "--target group requires --group-slug"

[ -f "$SOURCE_PATH" ] || deny_delivery invalid_resource
ROOT="$(cd "$ROOT" && pwd)"
if [ -n "$GROUP_SLUG" ] && ! permissions_group_authorized "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG"; then
  deny_group_access
fi
SOURCE_ABS="$(resolve_path "$SOURCE_PATH")" || die "cannot resolve file path: $SOURCE_PATH"
SOURCE_LOCATION_ABS="$(absolute_path "$SOURCE_PATH")" || die "cannot resolve source path location: $SOURCE_PATH"

WORKSPACE_ARGS=(--root "$ROOT" --platform "$PLATFORM" --user-id "$USER_ID" --user-slug "$USER_SLUG")
[ -z "$CHAT_ID" ] || WORKSPACE_ARGS+=(--chat-id "$CHAT_ID")
[ -z "$GROUP_SLUG" ] || WORKSPACE_ARGS+=(--group-slug "$GROUP_SLUG")
[ -z "$IDENTITY_KEY" ] || WORKSPACE_ARGS+=(--identity-key "$IDENTITY_KEY")
[ -z "$NAME" ] || WORKSPACE_ARGS+=(--name "$NAME")
[ -z "$GROUP_NAME" ] || WORKSPACE_ARGS+=(--group-name "$GROUP_NAME")
WORKSPACE_EXPORTS="$(bash "$SCRIPT_DIR/knot-workspace.sh" "${WORKSPACE_ARGS[@]}")"
USER_WORKSPACE="$(workspace_export KNOT_USER_WORKSPACE "$WORKSPACE_EXPORTS")"
GROUP_WORKSPACE="$(workspace_export KNOT_GROUP_WORKSPACE "$WORKSPACE_EXPORTS")"

if [ -L "$USER_WORKSPACE" ] || [ -L "$USER_WORKSPACE/deliverables" ]; then
  deny_delivery_with_message symlink_denied "current user workspace and deliverables must not be symlinks"
fi

if [ -n "$GROUP_WORKSPACE" ] && { [ -L "$GROUP_WORKSPACE" ] || [ -L "$GROUP_WORKSPACE/deliverables" ]; }; then
  deny_delivery_with_message symlink_denied "current group workspace and deliverables must not be symlinks"
fi

USER_REAL="$(resolve_path "$USER_WORKSPACE")" || die "cannot resolve user workspace"
GROUP_REAL=""
if [ -n "$GROUP_WORKSPACE" ]; then
  GROUP_REAL="$(resolve_path "$GROUP_WORKSPACE")" || die "cannot resolve group workspace"
fi
USERS_DIR="$(resolve_path "$ROOT/workspace/users")" || die "cannot resolve users directory"
GROUPS_DIR="$(resolve_path "$ROOT/workspace/groups")" || die "cannot resolve groups directory"
CONVERSATIONS_DIR="$(resolve_path "$ROOT/workspace/conversations" 2>/dev/null || true)"

USER_DELIVERABLES_DIR="$(resolve_path "$USER_WORKSPACE/deliverables")" || die "cannot resolve user deliverables directory"
GROUP_DELIVERABLES_DIR=""
if [ -n "$GROUP_WORKSPACE" ]; then
  GROUP_DELIVERABLES_DIR="$(resolve_path "$GROUP_WORKSPACE/deliverables")" || die "cannot resolve group deliverables directory"
fi

reject_non_current_workspace_source "$SOURCE_ABS"
reject_non_current_workspace_source "$SOURCE_LOCATION_ABS"

if [ -z "$OUTPUT_NAME" ]; then
  OUTPUT_NAME="$(basename "$SOURCE_ABS")"
fi

case "$OUTPUT_NAME" in
  ""|"."|".."|*$'\n'*|*/*)
    die "--output-name must be a single file name"
    ;;
esac

DEST_DIR="$USER_DELIVERABLES_DIR"
if [ "$TARGET" = "group" ]; then
  DEST_DIR="$GROUP_DELIVERABLES_DIR"
fi

if path_is_under "$SOURCE_ABS" "$DEST_DIR"; then
  DEST_PATH="$SOURCE_ABS"
else
  DEST_PATH="$(unique_path "$DEST_DIR" "$OUTPUT_NAME")"
  cp -p "$SOURCE_ABS" "$DEST_PATH"
fi

ATTACH_ARGS=(--root "$ROOT" --platform "$PLATFORM" --user-id "$USER_ID" --user-slug "$USER_SLUG" --kind "$KIND" --path "$DEST_PATH")
[ -z "$CHAT_ID" ] || ATTACH_ARGS+=(--chat-id "$CHAT_ID")
[ -z "$GROUP_SLUG" ] || ATTACH_ARGS+=(--group-slug "$GROUP_SLUG")
[ -z "$IDENTITY_KEY" ] || ATTACH_ARGS+=(--identity-key "$IDENTITY_KEY")
[ -z "$CONVERSATION_DIR" ] || ATTACH_ARGS+=(--conversation-dir "$CONVERSATION_DIR")
bash "$SCRIPT_DIR/knot-attachment.sh" "${ATTACH_ARGS[@]}"
