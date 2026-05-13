#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM=""
CHAT_ID=""
USER_ID=""
KIND=""
FILE_PATH=""

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-attachment.sh --platform NAME --chat-id ID --user-id ID --kind image|file --path FILE

Validates that FILE exists under the current session deliverables directory,
then prints a cc-connect attachment block.
EOF
}

die() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
}

resolve_path() {
  local path="$1"
  local dir
  local base

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  [ -d "$dir" ] || return 1
  printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      ROOT="$1"
      ;;
    --platform)
      shift
      [ "$#" -gt 0 ] || die "--platform requires a value"
      PLATFORM="$1"
      ;;
    --chat-id)
      shift
      [ "$#" -gt 0 ] || die "--chat-id requires a value"
      CHAT_ID="$1"
      ;;
    --user-id)
      shift
      [ "$#" -gt 0 ] || die "--user-id requires a value"
      USER_ID="$1"
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
[ -n "$CHAT_ID" ] || die "--chat-id is required"
[ -n "$USER_ID" ] || die "--user-id is required"
[ -n "$KIND" ] || die "--kind is required"
[ -n "$FILE_PATH" ] || die "--path is required"

case "$KIND" in
  image|file)
    ;;
  *)
    die "--kind must be image or file"
    ;;
esac

[ -f "$FILE_PATH" ] || die "file not found: $FILE_PATH"

ROOT="$(cd "$ROOT" && pwd)"
SESSION_DIR="$(bash "$SCRIPT_DIR/knot-session.sh" --root "$ROOT" --platform "$PLATFORM" --chat-id "$CHAT_ID" --user-id "$USER_ID" --no-metadata)"
DELIVERABLES_DIR="$(resolve_path "$SESSION_DIR/deliverables")" || die "cannot resolve deliverables directory"
ABS_FILE="$(resolve_path "$FILE_PATH")" || die "cannot resolve file path: $FILE_PATH"

case "$ABS_FILE" in
  "$DELIVERABLES_DIR"/*)
    ;;
  *)
    die "attachment must be inside the current session deliverables directory: $DELIVERABLES_DIR"
    ;;
esac

printf '```cc-connect-attachments\n'
printf '%s: %s\n' "$KIND" "$ABS_FILE"
printf '```\n'
