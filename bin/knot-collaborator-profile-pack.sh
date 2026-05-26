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

usage() {
  cat <<'EOF'
Usage: bash bin/knot-collaborator-profile-pack.sh pack --actor-user SLUG --active-workspace DIR --user-workspace DIR [options]

Options:
  --root DIR
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

collab_profile_deny() {
  local reason_code="$1"
  local message="$2"

  knot_audit_record collab.profile.pack.denied denied "$reason_code" || true
  die "$message"
}

write_profile_source() {
  local path="$1"
  local rel

  rel="$(collab_profile_relative_to_root "$path")" ||
    collab_profile_deny invalid_resource "collaborator profile source is outside Knot root: $path"

  printf '### %s\n\n' "$rel"
  printf 'kind: collaborator_profile\n'
  printf 'sha256: %s\n\n' "$(file_sha256 "$path")"
  printf '```markdown\n'
  cat "$path"
  case "$(tail -c 1 "$path" 2>/dev/null || true)" in
    "")
      ;;
    *)
      printf '\n'
      ;;
  esac
  printf '```\n\n'
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

[ "$COMMAND" = "pack" ] || die "first argument must be pack"

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

umask 077

PROFILE_DIR="$USER_WORKSPACE/collaboration"
CONTEXT_DIR="$USER_WORKSPACE/.knot"
PACK_PATH="$CONTEXT_DIR/collaborator-profile-pack.md"
ensure_dir_no_symlink "$USER_WORKSPACE" "user workspace"
ensure_dir_no_symlink "$PROFILE_DIR" "collaboration profile"
ensure_dir_no_symlink "$CONTEXT_DIR" "user runtime context"
chmod 700 "$PROFILE_DIR" "$CONTEXT_DIR"

PROFILE_FILE="$PROFILE_DIR/profile.md"
collab_profile_ensure_owner_only_file "$PROFILE_FILE"
collab_profile_validate_content "$PROFILE_FILE"

tmp_pack="$(mktemp "$CONTEXT_DIR/.collaborator-profile-pack.md.tmp.XXXXXX")"
chmod 600 "$tmp_pack"

{
  printf '# Knot Collaborator Profile Pack\n\n'
  printf 'scope: collaborator_profile\n'
  printf 'actor_user: %s\n' "$USER_SLUG"
  printf 'active_workspace: %s\n' "$(collab_profile_relative_to_root "$ACTIVE_WORKSPACE")"
  printf 'user_workspace: %s\n' "$(collab_profile_relative_to_root "$USER_WORKSPACE")"
  printf 'write_target: %s\n\n' "$(collab_profile_relative_to_root "$PROFILE_FILE")"
  printf '## Sources\n\n'
  write_profile_source "$PROFILE_FILE"
} > "$tmp_pack"

previous_pack="$(mktemp "$CONTEXT_DIR/.collaborator-profile-pack.md.previous.XXXXXX")"
had_previous_pack=0
if [ -f "$PACK_PATH" ]; then
  cp "$PACK_PATH" "$previous_pack"
  chmod 600 "$previous_pack"
  had_previous_pack=1
else
  rm -f "$previous_pack"
fi

mv "$tmp_pack" "$PACK_PATH"
chmod 600 "$PACK_PATH"

if ! knot_audit_record collab.profile.pack.generated recorded; then
  if [ "$had_previous_pack" -eq 1 ]; then
    mv "$previous_pack" "$PACK_PATH"
    chmod 600 "$PACK_PATH"
  else
    rm -f "$PACK_PATH"
  fi
  die "cannot record collaborator profile pack event"
fi
rm -f "$previous_pack"
printf '%s\n' "$PACK_PATH"
