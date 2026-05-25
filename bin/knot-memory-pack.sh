#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"

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
Usage: bash bin/knot-memory-pack.sh pack --actor-user SLUG --active-workspace DIR --user-workspace DIR [options]

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

deny_memory_pack() {
  local reason_code="$1"
  local message="$2"

  knot_audit_record memory.pack.denied denied "$reason_code" || true
  die "$message"
}

relative_to_root() {
  local path="$1"
  local abs

  abs="$(absolute_path "$path")" || return 1
  case "$abs" in
    "$ROOT_REAL"/*)
      printf '%s\n' "${abs#"$ROOT_REAL/"}"
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_owner_only_file() {
  local path="$1"

  if [ -L "$path" ]; then
    deny_memory_pack symlink_denied "memory file must not be a symlink: $path"
  fi
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    deny_memory_pack invalid_resource "memory path is not a file: $path"
  fi
  if [ ! -f "$path" ]; then
    : > "$path"
  fi
  chmod 600 "$path"
}

permissions_actor_workspace_by_identity_key() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] || return 0
  awk -F'|' \
    -v identity_key="$IDENTITY_KEY" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      workspace = trim($3)
      row_platform = trim($4)
      row_user_id = trim($5)
      row_identity_key = trim($8)
      if (workspace == "Workspace" || workspace == "---" || workspace == "") {
        next
      }

      if (identity_key != "" && row_identity_key != "" && row_identity_key == identity_key) {
        print workspace
      }
    }
  ' "$permissions_file" | sort -u
}

permissions_actor_workspace_by_platform_user() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] || return 0
  awk -F'|' \
    -v platform="$PLATFORM" \
    -v user_id="$USER_ID" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      workspace = trim($3)
      row_platform = trim($4)
      row_user_id = trim($5)
      if (workspace == "Workspace" || workspace == "---" || workspace == "") {
        next
      }

      if (platform != "" && user_id != "" && row_platform == platform && row_user_id == user_id) {
        print workspace
      }
    }
  ' "$permissions_file" | sort -u
}

validate_identity_matches_actor() {
  local label="$1"
  local matches="$2"
  local required="$3"
  local permissions_file="$ROOT/workspace/admin/permissions.md"
  local count
  local resolved_workspace

  [ -f "$permissions_file" ] || return 0

  count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  case "$count" in
    0)
      [ "$required" -eq 0 ] && return 0
      deny_memory_pack memory_identity_unresolved "$label is not mapped in permissions"
      ;;
    1)
      resolved_workspace="$(printf '%s\n' "$matches" | sed '/^$/d' | head -n 1)"
      [ "$resolved_workspace" = "$USER_SLUG" ] || deny_memory_pack memory_workspace_mismatch "$label workspace does not match actor"
      ;;
    *)
      deny_memory_pack memory_identity_ambiguous "$label maps to multiple workspaces"
      ;;
  esac
}

validate_permissions_actor_scope() {
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] || deny_memory_pack memory_identity_unresolved "permissions source of truth is missing"
  if [ -n "$IDENTITY_KEY" ]; then
    validate_identity_matches_actor "identity key" "$(permissions_actor_workspace_by_identity_key)" 1
    validate_identity_matches_actor "platform user id" "$(permissions_actor_workspace_by_platform_user)" 0
  else
    validate_identity_matches_actor "platform user id" "$(permissions_actor_workspace_by_platform_user)" 1
  fi
}

deny_if_symlink() {
  local path="$1"
  local label="$2"

  if [ -L "$path" ]; then
    deny_memory_pack symlink_denied "$label must not be a symlink: $path"
  fi
}

write_memory_source() {
  local label="$1"
  local path="$2"
  local rel

  rel="$(relative_to_root "$path")" || deny_memory_pack invalid_resource "memory source is outside Knot root: $path"

  printf '### %s\n\n' "$rel"
  printf 'kind: %s\n' "$label"
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
  deny_memory_pack symlink_denied "Knot root must not be a symlink"
fi

ROOT="$(cd "$ROOT" && pwd -P)"
ROOT_REAL="$ROOT"

[ -n "$USER_SLUG" ] || deny_memory_pack memory_identity_unresolved "--actor-user or KNOT_ACTOR_USER is required"
validate_slug "--actor-user" "$USER_SLUG"
[ -z "$GROUP_SLUG" ] || validate_slug "--group-slug" "$GROUP_SLUG"

[ -z "$GROUP_SLUG" ] || deny_memory_pack unauthorized_group "group-scoped memory packs are not implemented yet"
validate_permissions_actor_scope

EXPECTED_USER_WORKSPACE="$ROOT/workspace/users/$USER_SLUG"
[ -n "$USER_WORKSPACE" ] || deny_memory_pack memory_identity_unresolved "--user-workspace or KNOT_USER_WORKSPACE is required"
[ -n "$ACTIVE_WORKSPACE" ] || deny_memory_pack memory_identity_unresolved "--active-workspace or KNOT_ACTIVE_WORKSPACE is required"

USER_WORKSPACE="$(absolute_path "$USER_WORKSPACE")" || deny_memory_pack memory_workspace_mismatch "cannot resolve user workspace"
ACTIVE_WORKSPACE="$(absolute_path "$ACTIVE_WORKSPACE")" || deny_memory_pack memory_workspace_mismatch "cannot resolve active workspace"
EXPECTED_USER_WORKSPACE="$(absolute_path "$EXPECTED_USER_WORKSPACE")" || deny_memory_pack memory_workspace_mismatch "cannot resolve expected user workspace"

[ "$USER_WORKSPACE" = "$EXPECTED_USER_WORKSPACE" ] || deny_memory_pack memory_workspace_mismatch "user workspace does not match actor"
[ "$ACTIVE_WORKSPACE" = "$USER_WORKSPACE" ] || deny_memory_pack memory_workspace_mismatch "active workspace must equal user workspace for direct memory pack"

deny_if_symlink "$ROOT/workspace" "workspace root"
deny_if_symlink "$ROOT/workspace/users" "users root"
deny_if_symlink "$USER_WORKSPACE" "user workspace"

umask 077

MEMORY_DIR="$USER_WORKSPACE/memory"
CONTEXT_DIR="$USER_WORKSPACE/.knot"
PACK_PATH="$CONTEXT_DIR/memory-pack.md"
ensure_dir_no_symlink "$USER_WORKSPACE" "user workspace"
ensure_dir_no_symlink "$MEMORY_DIR" "user memory"
ensure_dir_no_symlink "$CONTEXT_DIR" "user runtime context"
chmod 700 "$MEMORY_DIR" "$CONTEXT_DIR"

PROFILE_FILE="$MEMORY_DIR/profile.md"
ACTIVE_FILE="$MEMORY_DIR/active.md"
FOLLOWUPS_FILE="$MEMORY_DIR/followups.md"
ensure_owner_only_file "$PROFILE_FILE"
ensure_owner_only_file "$ACTIVE_FILE"
ensure_owner_only_file "$FOLLOWUPS_FILE"

tmp_pack="$(mktemp "$CONTEXT_DIR/.memory-pack.md.tmp.XXXXXX")"
chmod 600 "$tmp_pack"

{
  printf '# Knot Memory Pack\n\n'
  printf 'scope: direct\n'
  printf 'actor_user: %s\n' "$USER_SLUG"
  printf 'active_workspace: %s\n' "$(relative_to_root "$ACTIVE_WORKSPACE")"
  printf 'user_workspace: %s\n\n' "$(relative_to_root "$USER_WORKSPACE")"
  printf 'write_targets:\n'
  printf -- '- %s\n' "$(relative_to_root "$ACTIVE_FILE")"
  printf -- '- %s\n\n' "$(relative_to_root "$FOLLOWUPS_FILE")"
  printf '## Sources\n\n'
  write_memory_source profile "$PROFILE_FILE"
  write_memory_source active "$ACTIVE_FILE"
  write_memory_source followups "$FOLLOWUPS_FILE"
} > "$tmp_pack"

mv "$tmp_pack" "$PACK_PATH"
chmod 600 "$PACK_PATH"

knot_audit_record memory.pack.generated recorded || true
printf '%s\n' "$PACK_PATH"
