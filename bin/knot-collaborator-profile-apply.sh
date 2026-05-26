#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"
# shellcheck source=lib/knot/collaborator-profile-direct.sh
. "$DEFAULT_ROOT/lib/knot/collaborator-profile-direct.sh"

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
PATCH_PATH=""
TMP_OUTPUT=""
TMP_DIFF=""
TMP_BACKUP=""
LOCK_DIR=""
LOCK_HELD=0

usage() {
  cat <<'EOF'
Usage: bash bin/knot-collaborator-profile-apply.sh apply --patch FILE --actor-user SLUG --active-workspace DIR --user-workspace DIR [options]

Options:
  --root DIR
  --patch FILE
  --platform NAME
  --chat-id ID
  --user-id ID
  --identity-key KEY
  --actor-user SLUG
  --group-slug SLUG
  --active-workspace DIR
  --user-workspace DIR
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

collab_profile_deny() {
  local reason_code="$1"
  local message="$2"

  knot_audit_record collab.profile.patch.denied denied "$reason_code" || true
  die "$message"
}

acquire_apply_lock() {
  LOCK_DIR="$USER_WORKSPACE/.knot/collaborator-profile-apply.lock"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    collab_profile_deny collab_profile_patch_conflict "another collaborator profile patch apply is already in progress"
  fi
  LOCK_HELD=1
}

atomic_replace() {
  local source="$1"
  local target="$2"

  python3 - "$source" "$target" <<'PY'
import os
import sys

source, target = sys.argv[1:]
with open(source, "rb+") as output:
    output.flush()
    os.fsync(output.fileno())
os.chmod(source, 0o600)
os.replace(source, target)
directory = os.open(os.path.dirname(target), os.O_DIRECTORY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
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
  collab_profile_deny symlink_denied "Knot root must not be a symlink"
fi
ROOT="$(cd "$ROOT" && pwd -P)"
ROOT_REAL="$ROOT"

collab_profile_validate_actor_scope

[ -n "$PATCH_PATH" ] || collab_profile_deny collab_profile_patch_invalid "--patch is required"
collab_profile_deny_if_symlink "$USER_WORKSPACE/collaboration" "collaboration profile"
collab_profile_deny_if_symlink "$USER_WORKSPACE/.knot" "user runtime context"
collab_profile_deny_if_symlink "$PATCH_PATH" "collaborator profile patch proposal"
[ -f "$PATCH_PATH" ] || collab_profile_deny collab_profile_patch_invalid "collaborator profile patch proposal is not a file"

PATCH_PATH="$(absolute_path "$PATCH_PATH")" ||
  collab_profile_deny collab_profile_patch_invalid "cannot resolve collaborator profile patch proposal"
EXPECTED_PATCH_PATH="$(absolute_path "$USER_WORKSPACE/.knot/collaborator-profile.patch")" ||
  collab_profile_deny collab_profile_patch_invalid "cannot resolve expected collaborator profile patch proposal"
[ "$PATCH_PATH" = "$EXPECTED_PATCH_PATH" ] ||
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch proposal must be in the active runtime context"
chmod 600 "$PATCH_PATH"
acquire_apply_lock

TARGET_REL="$(sed -n '1s/^target: //p' "$PATCH_PATH")"
BASE_SHA256="$(sed -n '2s/^base_sha256: //p' "$PATCH_PATH")"
[ "$(sed -n '3p' "$PATCH_PATH")" = "" ] ||
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch metadata must be followed by a blank line"
[ -n "$TARGET_REL" ] ||
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch target is missing"
printf '%s' "$BASE_SHA256" | grep -Eq '^[0-9a-f]{64}$' ||
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch base_sha256 is invalid"

case "$TARGET_REL" in
  "workspace/users/$USER_SLUG/collaboration/profile.md")
    ;;
  *)
    collab_profile_deny collab_profile_patch_invalid "collaborator profile patch target is not the actor profile"
    ;;
esac

[ "$(sed -n '4p' "$PATCH_PATH")" = "--- a/$TARGET_REL" ] ||
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch source header does not match target"
[ "$(sed -n '5p' "$PATCH_PATH")" = "+++ b/$TARGET_REL" ] ||
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch destination header does not match target"

TARGET_PATH="$ROOT/$TARGET_REL"
collab_profile_deny_if_symlink "$TARGET_PATH" "collaborator profile patch target"
[ -f "$TARGET_PATH" ] ||
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch target is not an existing file"
[ "$(file_sha256 "$TARGET_PATH")" = "$BASE_SHA256" ] ||
  collab_profile_deny collab_profile_patch_conflict "collaborator profile patch base hash no longer matches target"

TMP_DIFF="$(mktemp "$USER_WORKSPACE/.knot/.collaborator-profile.patch.diff.XXXXXX")"
TMP_OUTPUT="$(mktemp "$USER_WORKSPACE/collaboration/.collaborator-profile-apply.md.XXXXXX")"
chmod 600 "$TMP_DIFF" "$TMP_OUTPUT"
tail -n +4 "$PATCH_PATH" > "$TMP_DIFF"

if ! /usr/bin/patch -s -f -F 0 -o "$TMP_OUTPUT" "$TARGET_PATH" "$TMP_DIFF" >/dev/null 2>&1; then
  collab_profile_deny collab_profile_patch_invalid "collaborator profile patch is not an applicable unified diff"
fi

collab_profile_validate_content "$TMP_OUTPUT"
TMP_BACKUP="$(mktemp "$USER_WORKSPACE/collaboration/.collaborator-profile-before.md.XXXXXX")"
cp "$TARGET_PATH" "$TMP_BACKUP"
chmod 600 "$TMP_BACKUP"
atomic_replace "$TMP_OUTPUT" "$TARGET_PATH" ||
  collab_profile_deny write_failed "cannot atomically replace collaborator profile"
TMP_OUTPUT=""
chmod 600 "$TARGET_PATH"

if ! knot_audit_record collab.profile.patch.applied recorded; then
  atomic_replace "$TMP_BACKUP" "$TARGET_PATH" ||
    die "cannot restore collaborator profile after audit failure"
  TMP_BACKUP=""
  die "cannot record collaborator profile patch apply event"
fi
rm -f "$TMP_BACKUP"
TMP_BACKUP=""
printf '%s\n' "$TARGET_PATH"
