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
KIND=""
FILE_PATH=""

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
case "$FILE_PATH" in
  *$'\n'*|*$'\r'*)
    knot_delivery_deny attachment invalid_resource "$KIND" "$FILE_PATH" "$GROUP_SLUG"
    ;;
esac

case "$KIND" in
  image|file)
    ;;
  *)
    die "--kind must be image or file"
    ;;
esac

[ -f "$FILE_PATH" ] || knot_delivery_deny attachment invalid_resource "$KIND" "$FILE_PATH" "$GROUP_SLUG"
ROOT="$(cd "$ROOT" && pwd)"
if [ -n "$GROUP_SLUG" ] && ! permissions_group_authorized "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG"; then
  knot_delivery_deny_group_access attachment "$GROUP_SLUG"
fi
WORKSPACE_ARGS=(--root "$ROOT" --platform "$PLATFORM" --user-id "$USER_ID" --user-slug "$USER_SLUG" --no-create)
[ -z "$CHAT_ID" ] || WORKSPACE_ARGS+=(--chat-id "$CHAT_ID")
[ -z "$GROUP_SLUG" ] || WORKSPACE_ARGS+=(--group-slug "$GROUP_SLUG")
[ -z "$IDENTITY_KEY" ] || WORKSPACE_ARGS+=(--identity-key "$IDENTITY_KEY")
WORKSPACE_EXPORTS="$(bash "$SCRIPT_DIR/knot-workspace.sh" "${WORKSPACE_ARGS[@]}")"
SCOPE="$(workspace_export KNOT_SCOPE "$WORKSPACE_EXPORTS")"
USER_WORKSPACE="$(workspace_export KNOT_USER_WORKSPACE "$WORKSPACE_EXPORTS")"
GROUP_WORKSPACE="$(workspace_export KNOT_GROUP_WORKSPACE "$WORKSPACE_EXPORTS")"

if [ -L "$USER_WORKSPACE" ] || [ -L "$USER_WORKSPACE/deliverables" ]; then
  knot_delivery_deny_with_message symlink_denied "$KIND" "$FILE_PATH" "current user workspace and deliverables must not be symlinks"
fi

if [ -n "$GROUP_WORKSPACE" ] && { [ -L "$GROUP_WORKSPACE" ] || [ -L "$GROUP_WORKSPACE/deliverables" ]; }; then
  knot_delivery_deny_with_message symlink_denied "$KIND" "$FILE_PATH" "current group workspace and deliverables must not be symlinks"
fi

USER_DELIVERABLES_DIR="$(resolve_path "$USER_WORKSPACE/deliverables")" || die "cannot resolve user deliverables directory"
GROUP_DELIVERABLES_DIR=""
if [ -n "$GROUP_WORKSPACE" ]; then
  GROUP_DELIVERABLES_DIR="$(resolve_path "$GROUP_WORKSPACE/deliverables")" || die "cannot resolve group deliverables directory"
fi

ABS_FILE="$(resolve_path "$FILE_PATH")" || die "cannot resolve file path: $FILE_PATH"
CONVERSATIONS_DIR="$(resolve_path "$ROOT/workspace/conversations" 2>/dev/null || true)"
if find "$ABS_FILE" -maxdepth 0 -type f -links +1 -print -quit | grep -q .; then
  knot_delivery_deny attachment hardlink_denied "$KIND" "$FILE_PATH" "$GROUP_SLUG"
fi

if [ -n "$CONVERSATIONS_DIR" ]; then
  case "$ABS_FILE" in
    "$CONVERSATIONS_DIR"/*)
      knot_delivery_deny attachment conversation_source_denied "$KIND" "$FILE_PATH" "$GROUP_SLUG"
      ;;
  esac
fi

if [ "$SCOPE" = "direct" ] && path_is_under "$ABS_FILE" "$USER_DELIVERABLES_DIR"; then
  :
elif [ "$SCOPE" = "group" ] && [ -n "$GROUP_DELIVERABLES_DIR" ] && path_is_under "$ABS_FILE" "$GROUP_DELIVERABLES_DIR"; then
  knot_audit_record group.access.allowed allowed
else
  knot_delivery_deny attachment outside_deliverables "$KIND" "$FILE_PATH" "$GROUP_SLUG"
fi

knot_audit_record delivery.verified allowed "" "$KIND" "$ABS_FILE"

printf '```cc-connect-attachments\n'
printf '%s: %s\n' "$KIND" "$ABS_FILE"
printf '```\n'
