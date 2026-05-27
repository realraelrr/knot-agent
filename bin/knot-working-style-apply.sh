#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"
# shellcheck source=lib/knot/working-style.sh
. "$DEFAULT_ROOT/lib/knot/working-style.sh"

COMMAND="${1:-}"
[ "$#" -eq 0 ] || shift

PLATFORM="${KNOT_PLATFORM:-}"
CHAT_ID="${KNOT_CHAT_ID:-}"
USER_ID="${KNOT_PLATFORM_USER_ID:-}"
IDENTITY_KEY="${KNOT_IDENTITY_KEY:-}"
USER_SLUG="${KNOT_ACTOR_USER:-}"
GROUP_SLUG="${KNOT_GROUP_SLUG:-${KNOT_SOURCE_GROUP:-}}"
CONVERSATION_DIR="${KNOT_CONVERSATION_DIR:-}"
ACTIVE_WORKSPACE="${KNOT_ACTIVE_WORKSPACE:-}"
USER_WORKSPACE="${KNOT_USER_WORKSPACE:-}"
ACTOR_WORKSPACE="${KNOT_ACTOR_WORKSPACE:-}"
SCOPE="${KNOT_SCOPE:-}"
PATCH_PATH=""
EXPLICIT_ACTOR_WORKSPACE=0
TMP_OUTPUT=""
TMP_DIFF=""
TMP_BACKUP=""
LOCK_DIR=""
LOCK_HELD=0

usage() {
  cat <<'EOF'
Usage: bash bin/knot-working-style-apply.sh apply --patch FILE --actor-user SLUG --active-workspace DIR --user-workspace DIR [options]

Options:
  --root DIR
  --patch FILE
  --platform NAME
  --chat-id ID
  --user-id ID
  --identity-key KEY
  --actor-user SLUG
  --group-slug SLUG
  --scope direct|group
  --active-workspace DIR
  --user-workspace DIR
  --actor-workspace DIR
  --conversation-dir DIR
  --help, -h
EOF
}

cleanup() {
  [ -z "$TMP_OUTPUT" ] || rm -f "$TMP_OUTPUT"
  [ -z "$TMP_DIFF" ] || rm -f "$TMP_DIFF"
  [ -z "$TMP_BACKUP" ] || rm -f "$TMP_BACKUP"
  if [ "$LOCK_HELD" -eq 1 ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM

working_style_deny() {
  local reason_code="$1"
  local message="$2"

  knot_audit_record working_style.patch.denied denied "$reason_code" || true
  die "$message"
}

acquire_apply_lock() {
  LOCK_DIR="$USER_WORKSPACE/.knot/style-apply.lock"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    working_style_deny working_style_patch_conflict "another working style patch apply is already in progress"
  fi
  LOCK_HELD=1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      ROOT="$1"
      ;;
    --patch)
      shift
      [ "$#" -gt 0 ] || die "--patch requires a value"
      PATCH_PATH="$1"
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
    --identity-key)
      shift
      [ "$#" -gt 0 ] || die "--identity-key requires a value"
      IDENTITY_KEY="$1"
      ;;
    --actor-user|--user-slug)
      option="$1"
      shift
      [ "$#" -gt 0 ] || die "$option requires a value"
      USER_SLUG="$1"
      ;;
    --group-slug)
      shift
      [ "$#" -gt 0 ] || die "--group-slug requires a value"
      GROUP_SLUG="$1"
      ;;
    --scope)
      shift
      [ "$#" -gt 0 ] || die "--scope requires a value"
      SCOPE="$1"
      ;;
    --active-workspace)
      shift
      [ "$#" -gt 0 ] || die "--active-workspace requires a value"
      ACTIVE_WORKSPACE="$1"
      ;;
    --user-workspace)
      shift
      [ "$#" -gt 0 ] || die "--user-workspace requires a value"
      USER_WORKSPACE="$1"
      ;;
    --actor-workspace)
      shift
      [ "$#" -gt 0 ] || die "--actor-workspace requires a value"
      ACTOR_WORKSPACE="$1"
      EXPLICIT_ACTOR_WORKSPACE=1
      ;;
    --conversation-dir)
      shift
      [ "$#" -gt 0 ] || die "--conversation-dir requires a value"
      CONVERSATION_DIR="$1"
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

[ "$COMMAND" = "apply" ] || die "first argument must be apply"
[ -n "$PLATFORM" ] || die "--platform or KNOT_PLATFORM is required"
[ -n "$CHAT_ID" ] || die "--chat-id or KNOT_CHAT_ID is required"
[ -n "$USER_ID" ] || die "--user-id or KNOT_PLATFORM_USER_ID is required"
[ -n "$CONVERSATION_DIR" ] || die "--conversation-dir or KNOT_CONVERSATION_DIR is required"

if [ -L "$ROOT" ]; then
  ROOT="$(cd "$ROOT" && pwd -P)" || die "cannot resolve Knot root"
  ROOT_REAL="$ROOT"
  working_style_deny symlink_denied "Knot root must not be a symlink"
fi
ROOT="$(cd "$ROOT" && pwd -P)"
ROOT_REAL="$ROOT"

working_style_validate_actor_scope

if [ "$SCOPE" = "group" ]; then
  working_style_deny working_style_workspace_mismatch "group scope cannot apply working style patches"
fi

[ -n "$PATCH_PATH" ] || working_style_deny working_style_patch_invalid "--patch is required"
working_style_deny_if_symlink "$USER_WORKSPACE/style.md" "working style"
working_style_deny_if_symlink "$USER_WORKSPACE/.knot" "user runtime context"
working_style_deny_if_symlink "$PATCH_PATH" "working style patch proposal"
[ -f "$PATCH_PATH" ] || working_style_deny working_style_patch_invalid "working style patch proposal is not a file"

PATCH_PATH="$(absolute_path "$PATCH_PATH")" ||
  working_style_deny working_style_patch_invalid "cannot resolve working style patch proposal"
EXPECTED_PATCH_PATH="$(absolute_path "$USER_WORKSPACE/.knot/style.patch")" ||
  working_style_deny working_style_patch_invalid "cannot resolve expected working style patch proposal"
[ "$PATCH_PATH" = "$EXPECTED_PATCH_PATH" ] ||
  working_style_deny working_style_patch_invalid "working style patch proposal must be in the active runtime context"
chmod 600 "$PATCH_PATH"
acquire_apply_lock

TARGET_REL="$(sed -n '1s/^target: //p' "$PATCH_PATH")"
BASE_SHA256="$(sed -n '2s/^base_sha256: //p' "$PATCH_PATH")"
[ "$(sed -n '3p' "$PATCH_PATH")" = "" ] ||
  working_style_deny working_style_patch_invalid "working style patch metadata must be followed by a blank line"
[ -n "$TARGET_REL" ] ||
  working_style_deny working_style_patch_invalid "working style patch target is missing"
printf '%s' "$BASE_SHA256" | grep -Eq '^[0-9a-f]{64}$' ||
  working_style_deny working_style_patch_invalid "working style patch base_sha256 is invalid"

case "$TARGET_REL" in
  "workspace/users/$USER_SLUG/style.md")
    ;;
  *)
    working_style_deny working_style_patch_invalid "working style patch target is not the actor style file"
    ;;
esac

[ "$(sed -n '4p' "$PATCH_PATH")" = "--- a/$TARGET_REL" ] ||
  working_style_deny working_style_patch_invalid "working style patch source header does not match target"
[ "$(sed -n '5p' "$PATCH_PATH")" = "+++ b/$TARGET_REL" ] ||
  working_style_deny working_style_patch_invalid "working style patch destination header does not match target"

TARGET_PATH="$ROOT/$TARGET_REL"
working_style_deny_if_symlink "$TARGET_PATH" "working style patch target"
[ -f "$TARGET_PATH" ] ||
  working_style_deny working_style_patch_invalid "working style patch target is not an existing file"
[ "$(file_sha256 "$TARGET_PATH")" = "$BASE_SHA256" ] ||
  working_style_deny working_style_patch_conflict "working style patch base hash no longer matches target"

TMP_DIFF="$(mktemp "$USER_WORKSPACE/.knot/.style.patch.diff.XXXXXX")"
TMP_OUTPUT="$(mktemp "$USER_WORKSPACE/.working-style-apply.md.XXXXXX")"
chmod 600 "$TMP_DIFF" "$TMP_OUTPUT"
tail -n +4 "$PATCH_PATH" > "$TMP_DIFF"

if ! /usr/bin/patch -s -f -F 0 -o "$TMP_OUTPUT" "$TARGET_PATH" "$TMP_DIFF" >/dev/null 2>&1; then
  working_style_deny working_style_patch_invalid "working style patch is not an applicable unified diff"
fi

working_style_validate_content "$TMP_OUTPUT" write
TMP_BACKUP="$(mktemp "$USER_WORKSPACE/.working-style-before.md.XXXXXX")"
cp "$TARGET_PATH" "$TMP_BACKUP"
chmod 600 "$TMP_BACKUP"
knot_atomic_replace "$TMP_OUTPUT" "$TARGET_PATH" ||
  working_style_deny write_failed "cannot atomically replace working style"
TMP_OUTPUT=""
chmod 600 "$TARGET_PATH"

if ! knot_audit_record working_style.patch.applied recorded; then
  knot_atomic_replace "$TMP_BACKUP" "$TARGET_PATH" ||
    die "cannot restore working style after audit failure"
  TMP_BACKUP=""
  die "cannot record working style patch apply event"
fi
rm -f "$TMP_BACKUP"
TMP_BACKUP=""
printf '%s\n' "$TARGET_PATH"
