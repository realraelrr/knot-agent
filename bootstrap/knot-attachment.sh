#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
. "$SCRIPT_DIR/lib.sh"
PLATFORM="${KNOT_PLATFORM:-}"
CHAT_ID="${KNOT_CHAT_ID:-}"
USER_ID="${KNOT_PLATFORM_USER_ID:-}"
USER_SLUG="${KNOT_ACTOR_USER:-}"
GROUP_SLUG="${KNOT_SOURCE_GROUP:-}"
IDENTITY_KEY="${KNOT_IDENTITY_KEY:-}"
KIND=""
FILE_PATH=""
EXPLICIT_CONTEXT=0
EXPLICIT_IDENTITY_KEY=0

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-attachment.sh --platform NAME --user-id ID --user-slug SLUG --kind image|file --path FILE [options]

Options:
  --root DIR          Knot root. Defaults to the parent of this script.
  --chat-id ID        Source chat id for conversation context.
  --group-slug SLUG   Current group workspace slug for group chats.
  --help, -h          Show this help.

Validates that FILE exists under the current user deliverables directory, or
under the current group deliverables directory when --group-slug is provided,
then prints a cc-connect attachment block.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      ROOT="$1"
      EXPLICIT_CONTEXT=1
      ;;
    --platform)
      shift
      [ "$#" -gt 0 ] || die "--platform requires a value"
      PLATFORM="$1"
      EXPLICIT_CONTEXT=1
      ;;
    --chat-id)
      shift
      [ "$#" -gt 0 ] || die "--chat-id requires a value"
      CHAT_ID="$1"
      EXPLICIT_CONTEXT=1
      ;;
    --user-id)
      shift
      [ "$#" -gt 0 ] || die "--user-id requires a value"
      USER_ID="$1"
      EXPLICIT_CONTEXT=1
      ;;
    --user-slug)
      shift
      [ "$#" -gt 0 ] || die "--user-slug requires a value"
      USER_SLUG="$1"
      EXPLICIT_CONTEXT=1
      ;;
    --group-slug)
      shift
      [ "$#" -gt 0 ] || die "--group-slug requires a value"
      GROUP_SLUG="$1"
      EXPLICIT_CONTEXT=1
      ;;
    --identity-key)
      shift
      [ "$#" -gt 0 ] || die "--identity-key requires a value"
      IDENTITY_KEY="$1"
      EXPLICIT_IDENTITY_KEY=1
      ;;
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

[ -n "$PLATFORM" ] || die "--platform is required"
[ -n "$USER_ID" ] || die "--user-id is required"
[ -n "$USER_SLUG" ] || die "--user-slug is required"
[ -n "$KIND" ] || die "--kind is required"
[ -n "$FILE_PATH" ] || die "--path is required"
if [ "$EXPLICIT_CONTEXT" -eq 1 ] && [ "$EXPLICIT_IDENTITY_KEY" -eq 0 ]; then
  IDENTITY_KEY=""
fi

case "$KIND" in
  image|file)
    ;;
  *)
    die "--kind must be image or file"
    ;;
esac

[ -f "$FILE_PATH" ] || die "file not found: $FILE_PATH"

ROOT="$(cd "$ROOT" && pwd)"
if [ -n "$GROUP_SLUG" ] && ! permissions_group_authorized "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG"; then
  die "group workspace is not authorized for this actor/context: $GROUP_SLUG"
fi
WORKSPACE_ARGS=(--root "$ROOT" --platform "$PLATFORM" --user-id "$USER_ID" --user-slug "$USER_SLUG" --no-create)
[ -z "$CHAT_ID" ] || WORKSPACE_ARGS+=(--chat-id "$CHAT_ID")
[ -z "$GROUP_SLUG" ] || WORKSPACE_ARGS+=(--group-slug "$GROUP_SLUG")
WORKSPACE_EXPORTS="$(bash "$SCRIPT_DIR/knot-workspace.sh" "${WORKSPACE_ARGS[@]}")"
USER_WORKSPACE="$(workspace_export KNOT_USER_WORKSPACE "$WORKSPACE_EXPORTS")"
GROUP_WORKSPACE="$(workspace_export KNOT_GROUP_WORKSPACE "$WORKSPACE_EXPORTS")"

if [ -L "$USER_WORKSPACE" ] || [ -L "$USER_WORKSPACE/deliverables" ]; then
  die "current user workspace and deliverables must not be symlinks"
fi

if [ -n "$GROUP_WORKSPACE" ] && { [ -L "$GROUP_WORKSPACE" ] || [ -L "$GROUP_WORKSPACE/deliverables" ]; }; then
  die "current group workspace and deliverables must not be symlinks"
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
      die "attachments cannot be sent from workspace/conversations"
      ;;
  esac
fi

case "$ABS_FILE" in
  "$USER_DELIVERABLES_DIR"/*)
    ;;
  "$GROUP_DELIVERABLES_DIR"/*)
    [ -n "$GROUP_DELIVERABLES_DIR" ] || die "attachments cannot be sent from another workspace"
    ;;
  *)
    die "attachment must be inside the current user or group deliverables directory"
    ;;
esac

printf '```cc-connect-attachments\n'
printf '%s: %s\n' "$KIND" "$ABS_FILE"
printf '```\n'
