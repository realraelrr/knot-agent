#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"
# shellcheck source=lib/knot/delivery.sh
. "$DEFAULT_ROOT/lib/knot/delivery.sh"
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
TARGET=""
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

reject_non_current_workspace_source() {
  local path="$1"

  [ -n "$path" ] || return 0

  if [ -n "$CONVERSATIONS_DIR" ] && path_is_under "$path" "$CONVERSATIONS_DIR"; then
    knot_delivery_deny deliver conversation_source_denied "$KIND" "$SOURCE_PATH" "$GROUP_SLUG"
  fi

  if path_is_under "$path" "$USERS_DIR" && ! path_is_under "$path" "$USER_REAL"; then
    knot_delivery_deny_with_message outside_deliverables "$KIND" "$SOURCE_PATH" "source file belongs to another user workspace"
  fi
  if [ "$SCOPE" = "group" ] && path_is_under "$path" "$USERS_DIR"; then
    knot_delivery_deny_with_message outside_deliverables "$KIND" "$SOURCE_PATH" "group scope cannot deliver files from user workspaces"
  fi

  if path_is_under "$path" "$GROUPS_DIR"; then
    if [ -z "$GROUP_REAL" ] || ! path_is_under "$path" "$GROUP_REAL"; then
      knot_delivery_deny_with_message outside_deliverables "$KIND" "$SOURCE_PATH" "source file belongs to another group workspace"
    fi
    if [ "$SCOPE" = "direct" ]; then
      knot_delivery_deny_with_message outside_deliverables "$KIND" "$SOURCE_PATH" "direct scope cannot deliver files from group workspaces"
    fi
  fi
}

source_is_allowed() {
  local path="$1"

  if [ "$SCOPE" = "direct" ]; then
    path_is_under "$path" "$USER_WORK_DIR" ||
      path_is_under "$path" "$USER_INBOX_DIR" ||
      path_is_under "$path" "$USER_DELIVERABLES_DIR"
    return
  fi

  if path_is_under "$path" "$ACTOR_REAL/.knot" ||
    path_is_under "$path" "$ACTOR_REAL/.state"; then
    return 1
  fi

  path_is_under "$path" "$ACTOR_REAL" ||
    path_is_under "$path" "$GROUP_DELIVERABLES_DIR"
}

while [ "$#" -gt 0 ]; do
  if parse_knot_context_field_arg "$@"; then
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

case "$KIND" in
  image|file)
    ;;
  *)
    die "--kind must be image or file"
    ;;
esac

[ -f "$SOURCE_PATH" ] || knot_delivery_deny deliver invalid_resource "$KIND" "$SOURCE_PATH" "$GROUP_SLUG"
ROOT="$(cd "$ROOT" && pwd)"
if [ -n "$GROUP_SLUG" ] && ! permissions_group_authorized "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG"; then
  knot_delivery_deny_group_access deliver "$GROUP_SLUG"
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
SCOPE="$(workspace_export KNOT_SCOPE "$WORKSPACE_EXPORTS")"
USER_WORKSPACE="$(workspace_export KNOT_USER_WORKSPACE "$WORKSPACE_EXPORTS")"
GROUP_WORKSPACE="$(workspace_export KNOT_GROUP_WORKSPACE "$WORKSPACE_EXPORTS")"
ACTOR_WORKSPACE="$(workspace_export KNOT_ACTOR_WORKSPACE "$WORKSPACE_EXPORTS")"

if [ -z "$TARGET" ]; then
  if [ "$SCOPE" = "group" ]; then
    TARGET="group"
  else
    TARGET="user"
  fi
fi

case "$TARGET" in
  user|group)
    ;;
  *)
    die "--target must be user or group"
    ;;
esac

if [ "$SCOPE" = "group" ] && [ "$TARGET" = "user" ]; then
  knot_delivery_deny_with_message outside_deliverables "$KIND" "$SOURCE_PATH" "group scope delivery must target current group deliverables"
fi
[ "$TARGET" != "group" ] || [ -n "$GROUP_SLUG" ] || die "--target group requires --group-slug"

if [ -L "$USER_WORKSPACE" ] || [ -L "$USER_WORKSPACE/deliverables" ]; then
  knot_delivery_deny_with_message symlink_denied "$KIND" "$SOURCE_PATH" "current user workspace and deliverables must not be symlinks"
fi

if [ -n "$GROUP_WORKSPACE" ] && { [ -L "$GROUP_WORKSPACE" ] || [ -L "$GROUP_WORKSPACE/deliverables" ]; }; then
  knot_delivery_deny_with_message symlink_denied "$KIND" "$SOURCE_PATH" "current group workspace and deliverables must not be symlinks"
fi

USER_REAL="$(resolve_path "$USER_WORKSPACE")" || die "cannot resolve user workspace"
ACTOR_REAL="$(resolve_path "$ACTOR_WORKSPACE")" || die "cannot resolve actor workspace"
GROUP_REAL=""
if [ -n "$GROUP_WORKSPACE" ]; then
  GROUP_REAL="$(resolve_path "$GROUP_WORKSPACE")" || die "cannot resolve group workspace"
fi
USERS_DIR="$(resolve_path "$ROOT/workspace/users")" || die "cannot resolve users directory"
GROUPS_DIR="$(resolve_path "$ROOT/workspace/groups")" || die "cannot resolve groups directory"
CONVERSATIONS_DIR="$(resolve_path "$ROOT/workspace/conversations" 2>/dev/null || true)"

USER_DELIVERABLES_DIR="$(resolve_path "$USER_WORKSPACE/deliverables")" || die "cannot resolve user deliverables directory"
USER_WORK_DIR="$(resolve_path "$USER_WORKSPACE/work")" || die "cannot resolve user work directory"
USER_INBOX_DIR="$(resolve_path "$USER_WORKSPACE/inbox")" || die "cannot resolve user inbox directory"
GROUP_DELIVERABLES_DIR=""
if [ -n "$GROUP_WORKSPACE" ]; then
  GROUP_DELIVERABLES_DIR="$(resolve_path "$GROUP_WORKSPACE/deliverables")" || die "cannot resolve group deliverables directory"
fi

reject_non_current_workspace_source "$SOURCE_ABS"
reject_non_current_workspace_source "$SOURCE_LOCATION_ABS"
source_is_allowed "$SOURCE_ABS" && source_is_allowed "$SOURCE_LOCATION_ABS" ||
  knot_delivery_deny_with_message outside_deliverables "$KIND" "$SOURCE_PATH" "source file is outside approved delivery sources for the current context"

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

COPIED_DEST=0
if path_is_under "$SOURCE_ABS" "$DEST_DIR"; then
  DEST_PATH="$SOURCE_ABS"
else
  DEST_PATH="$(unique_path "$DEST_DIR" "$OUTPUT_NAME")"
  cp -p "$SOURCE_ABS" "$DEST_PATH"
  COPIED_DEST=1
fi

ATTACH_ARGS=(--root "$ROOT" --platform "$PLATFORM" --user-id "$USER_ID" --user-slug "$USER_SLUG" --kind "$KIND" --path "$DEST_PATH")
[ -z "$CHAT_ID" ] || ATTACH_ARGS+=(--chat-id "$CHAT_ID")
[ -z "$GROUP_SLUG" ] || ATTACH_ARGS+=(--group-slug "$GROUP_SLUG")
[ -z "$IDENTITY_KEY" ] || ATTACH_ARGS+=(--identity-key "$IDENTITY_KEY")
[ -z "$CONVERSATION_DIR" ] || ATTACH_ARGS+=(--conversation-dir "$CONVERSATION_DIR")
if bash "$SCRIPT_DIR/knot-attachment.sh" "${ATTACH_ARGS[@]}"; then
  :
else
  status=$?
  if [ "$COPIED_DEST" -eq 1 ]; then
    rm -f -- "$DEST_PATH"
  fi
  exit "$status"
fi
