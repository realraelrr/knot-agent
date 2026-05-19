#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM=""
CHAT_ID=""
USER_ID=""
USER_SLUG=""
GROUP_SLUG=""
IDENTITY_KEY=""
NAME=""
GROUP_NAME=""
KIND=""
SOURCE_PATH=""
OUTPUT_NAME=""
TARGET="user"

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-deliver.sh --platform NAME --user-id ID --user-slug SLUG --kind image|file --path FILE [options]

Options:
  --root DIR           Knot root. Defaults to the parent of this script.
  --chat-id ID         Source chat id for conversation context.
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

die() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
}

resolve_path() {
  local path="$1"

  perl -MCwd=realpath -e '
    my $path = realpath($ARGV[0]);
    exit 1 unless defined $path;
    print "$path\n";
  ' "$path"
}

absolute_path() {
  local path="$1"

  local dir
  local base

  dir="$(cd "$(dirname "$path")" && pwd -P)" || return 1
  base="$(basename "$path")"
  printf '%s/%s\n' "$dir" "$base"
}

workspace_export() {
  local key="$1"
  local data="$2"

  printf '%s\n' "$data" | sed -n "s/^export ${key}='\\(.*\\)'$/\\1/p" | sed "s/'\\\\''/'/g" | tail -1
}

unique_path() {
  local dir="$1"
  local name="$2"
  local base="$name"
  local ext=""
  local i=1
  local candidate

  if [[ "$name" == *.* && "$name" != .* ]]; then
    base="${name%.*}"
    ext=".${name##*.}"
  fi

  candidate="$dir/$name"
  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    candidate="$dir/${base}-${i}${ext}"
    i=$((i + 1))
  done

  printf '%s\n' "$candidate"
}

path_is_under() {
  local path="$1"
  local dir="$2"

  [ -n "$dir" ] || return 1
  case "$path" in
    "$dir"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

reject_non_current_workspace_source() {
  local path="$1"

  [ -n "$path" ] || return 0

  if [ -n "$CONVERSATIONS_DIR" ] && path_is_under "$path" "$CONVERSATIONS_DIR"; then
    die "cannot deliver files from workspace/conversations"
  fi

  if path_is_under "$path" "$USERS_DIR" && ! path_is_under "$path" "$USER_REAL"; then
    die "source file belongs to another user workspace"
  fi

  if path_is_under "$path" "$GROUPS_DIR"; then
    if [ -z "$GROUP_REAL" ] || ! path_is_under "$path" "$GROUP_REAL"; then
      die "source file belongs to another group workspace"
    fi
  fi
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
    --user-slug)
      shift
      [ "$#" -gt 0 ] || die "--user-slug requires a value"
      USER_SLUG="$1"
      ;;
    --group-slug)
      shift
      [ "$#" -gt 0 ] || die "--group-slug requires a value"
      GROUP_SLUG="$1"
      ;;
    --identity-key)
      shift
      [ "$#" -gt 0 ] || die "--identity-key requires a value"
      IDENTITY_KEY="$1"
      ;;
    --name)
      shift
      [ "$#" -gt 0 ] || die "--name requires a value"
      NAME="$1"
      ;;
    --group-name)
      shift
      [ "$#" -gt 0 ] || die "--group-name requires a value"
      GROUP_NAME="$1"
      ;;
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

[ -n "$PLATFORM" ] || die "--platform is required"
[ -n "$USER_ID" ] || die "--user-id is required"
[ -n "$USER_SLUG" ] || die "--user-slug is required"
[ -n "$KIND" ] || die "--kind is required"
[ -n "$SOURCE_PATH" ] || die "--path is required"

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
[ -f "$SOURCE_PATH" ] || die "file not found: $SOURCE_PATH"

ROOT="$(cd "$ROOT" && pwd)"
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
  die "current user workspace and deliverables must not be symlinks"
fi

if [ -n "$GROUP_WORKSPACE" ] && { [ -L "$GROUP_WORKSPACE" ] || [ -L "$GROUP_WORKSPACE/deliverables" ]; }; then
  die "current group workspace and deliverables must not be symlinks"
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
bash "$SCRIPT_DIR/knot-attachment.sh" "${ATTACH_ARGS[@]}"
