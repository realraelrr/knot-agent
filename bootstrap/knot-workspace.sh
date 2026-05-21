#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
PLATFORM=""
CHAT_ID=""
USER_ID=""
USER_SLUG=""
GROUP_SLUG=""
IDENTITY_KEY=""
NAME=""
GROUP_NAME=""
CREATE_DIRS=1

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-workspace.sh --platform NAME --user-id ID [options]

Options:
  --root DIR           Knot root. Defaults to the parent of this script.
  --chat-id ID         Source chat id for conversation audit metadata.
  --user-slug SLUG     Current user workspace slug under workspace/users/.
  --group-slug SLUG    Current group workspace slug for group chats.
  --identity-key KEY   Stable identity/context key from the IM glue layer.
  --name NAME          Human display name to record in metadata.
  --group-name NAME    Human group display name to record in metadata.
  --no-create          Resolve paths and print exports without creating files.
  --help, -h           Show this help.

If --user-slug or --group-slug is omitted, this helper first tries
workspace/admin/permissions.md, then falls back to a deterministic safe slug.
Prints source-safe shell exports. The caller should start Codex with cwd set to
KNOT_ACTIVE_WORKSPACE.
EOF
}

hash_value() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print substr($1, 1, 12)}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print substr($1, 1, 12)}'
    return
  fi

  die "sha256sum or shasum is required"
}

safe_segment() {
  local raw="$1"
  local fallback="$2"
  local max_length="$3"
  local safe
  local hash

  safe="$(printf '%s' "$raw" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//; s/__*/_/g' | cut -c "1-$max_length")"
  if [ -z "$safe" ]; then
    safe="$fallback"
  fi

  hash="$(hash_value "$raw")"
  printf '%s-%s\n' "$safe" "$hash"
}

trim_field() {
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

permissions_lookup() {
  local want="$1"
  local permissions_file="$ROOT/workspace/admin/permissions.md"

  [ -f "$permissions_file" ] || return 0

  awk -F'|' \
    -v want="$want" \
    -v platform="$PLATFORM" \
    -v user_id="$USER_ID" \
    -v chat_id="$CHAT_ID" \
    -v identity_key="$IDENTITY_KEY" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      user = trim($2)
      workspace = trim($3)
      row_platform = trim($4)
      row_user_id = trim($5)
      group_slug = trim($6)
      row_chat_id = trim($7)
      row_identity_key = trim($8)
      if (user == "User" || user == "---" || workspace == "") {
        next
      }

      identity_match = (identity_key != "" && row_identity_key == identity_key)
      user_match = (row_platform == platform && row_user_id == user_id)
      chat_match = (chat_id != "" && row_platform == platform && row_chat_id == chat_id)

      if (want == "user" && (identity_match || user_match)) {
        print workspace
        exit
      }
      if (want == "group" && chat_match && (identity_match || user_match) && group_slug != "") {
        print group_slug
        exit
      }
    }
  ' "$permissions_file"
}

validate_metadata_value() {
  local label="$1"
  local value="$2"

  case "$value" in
    *$'\n'*|*$'\r'*|*$'\t'*)
      die "$label cannot contain tabs or newlines"
      ;;
  esac
}

emit_exports() {
  print_export KNOT_ROOT "$ROOT"
  print_export KNOT_ACTIVE_WORKSPACE "$USER_WORKSPACE"
  print_export KNOT_USER_WORKSPACE "$USER_WORKSPACE"
  print_export KNOT_GROUP_WORKSPACE "$GROUP_WORKSPACE"
  print_export KNOT_CONVERSATION_DIR "$CONVERSATION_DIR"
  print_export KNOT_ACTOR_USER "$USER_SLUG"
  print_export KNOT_SOURCE_GROUP "$GROUP_SLUG"
  print_export KNOT_PLATFORM "$PLATFORM"
  print_export KNOT_PLATFORM_USER_ID "$USER_ID"
  print_export KNOT_CHAT_ID "$CHAT_ID"
  print_export KNOT_IDENTITY_KEY "$IDENTITY_KEY"
}

write_kv_file() {
  local path="$1"
  shift

  {
    while [ "$#" -gt 0 ]; do
      printf '%s\t%s\n' "$1" "$2"
      shift 2
    done
  } > "$path"
}

append_unique_tsv_line() {
  local path="$1"
  local line="$2"

  touch "$path"
  if ! grep -Fxq -- "$line" "$path"; then
    printf '%s\n' "$line" >> "$path"
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
    --no-create)
      CREATE_DIRS=0
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

case "$PLATFORM" in
  dingtalk|feishu|wecom|weixin)
    ;;
  *)
    die "unsupported platform: $PLATFORM"
    ;;
esac

validate_metadata_value "--chat-id" "$CHAT_ID"
validate_metadata_value "--user-id" "$USER_ID"
validate_metadata_value "--identity-key" "$IDENTITY_KEY"
validate_metadata_value "--name" "$NAME"
validate_metadata_value "--group-name" "$GROUP_NAME"

ROOT="$(cd "$ROOT" && pwd)"

if [ -z "$USER_SLUG" ]; then
  USER_SLUG="$(permissions_lookup user | head -n 1 | trim_field)"
fi
PERMISSIONS_FILE="$ROOT/workspace/admin/permissions.md"
if [ -z "$GROUP_SLUG" ] && [ -n "$CHAT_ID" ]; then
  GROUP_SLUG="$(permissions_lookup group | head -n 1 | trim_field)"
fi
if [ -z "$USER_SLUG" ]; then
  if [ -n "$NAME" ]; then
    USER_SLUG="$(safe_segment "$NAME" "user" 60)"
  else
    USER_SLUG="$(safe_segment "$PLATFORM-$USER_ID" "user" 60)"
  fi
fi
if [ -z "$GROUP_SLUG" ] && [ -n "$GROUP_NAME" ] && [ ! -f "$PERMISSIONS_FILE" ]; then
  GROUP_SLUG="$(safe_segment "$GROUP_NAME" "group" 60)"
fi

validate_slug "--user-slug" "$USER_SLUG"
[ -z "$GROUP_SLUG" ] || validate_slug "--group-slug" "$GROUP_SLUG"
USER_WORKSPACE="$ROOT/workspace/users/$USER_SLUG"
GROUP_WORKSPACE=""
CONVERSATION_DIR=""
CONVERSATION_SEGMENT=""
CONTEXT_DIR="$USER_WORKSPACE/.knot"
CONTEXT_FILE="$CONTEXT_DIR/current-context.sh"

if [ -n "$GROUP_SLUG" ]; then
  GROUP_WORKSPACE="$ROOT/workspace/groups/$GROUP_SLUG"
fi

if [ -n "$CHAT_ID" ]; then
  CONVERSATION_SEGMENT="$(safe_segment "$CHAT_ID" "id" 80)"
  CONVERSATION_DIR="$ROOT/workspace/conversations/$PLATFORM/$CONVERSATION_SEGMENT"
fi

if [ -L "$USER_WORKSPACE" ]; then
  die "user workspace must not be a symlink: $USER_WORKSPACE"
fi

if [ -n "$GROUP_WORKSPACE" ] && [ -L "$GROUP_WORKSPACE" ]; then
  die "group workspace must not be a symlink: $GROUP_WORKSPACE"
fi

if [ "$CREATE_DIRS" -eq 1 ]; then
  ensure_dir_no_symlink "$ROOT/workspace" "workspace root"
  ensure_dir_no_symlink "$ROOT/workspace/users" "users root"
  ensure_dir_no_symlink "$ROOT/workspace/groups" "groups root"
  ensure_dir_no_symlink "$ROOT/workspace/conversations" "conversations root"

  ensure_dir_no_symlink "$USER_WORKSPACE" "user workspace"
  ensure_dir_no_symlink "$USER_WORKSPACE/inbox" "user inbox"
  ensure_dir_no_symlink "$USER_WORKSPACE/work" "user work"
  ensure_dir_no_symlink "$USER_WORKSPACE/deliverables" "user deliverables"
  ensure_dir_no_symlink "$USER_WORKSPACE/.state" "user state"
  ensure_dir_no_symlink "$USER_WORKSPACE/.state/tasks" "user task state"
  ensure_dir_no_symlink "$CONTEXT_DIR" "user context"

  if [ ! -f "$USER_WORKSPACE/profile.tsv" ] || [ -n "$NAME" ]; then
    write_kv_file "$USER_WORKSPACE/profile.tsv" \
      user_slug "$USER_SLUG" \
      name "$NAME"
  fi

  if [ ! -f "$USER_WORKSPACE/identities.tsv" ] || [ -n "$IDENTITY_KEY$NAME" ]; then
    append_unique_tsv_line "$USER_WORKSPACE/identities.tsv" \
      "$(printf '%s\t%s\t%s\t%s\n' "$PLATFORM" "$USER_ID" "$IDENTITY_KEY" "$NAME")"
  fi

  if [ -n "$GROUP_WORKSPACE" ]; then
    ensure_dir_no_symlink "$GROUP_WORKSPACE" "group workspace"
    ensure_dir_no_symlink "$GROUP_WORKSPACE/inbox" "group inbox"
    ensure_dir_no_symlink "$GROUP_WORKSPACE/work" "group work"
    ensure_dir_no_symlink "$GROUP_WORKSPACE/deliverables" "group deliverables"
    ensure_dir_no_symlink "$GROUP_WORKSPACE/.state" "group state"
    ensure_dir_no_symlink "$GROUP_WORKSPACE/.state/tasks" "group task state"

    if [ ! -f "$GROUP_WORKSPACE/profile.tsv" ] || [ -n "$GROUP_NAME" ]; then
      write_kv_file "$GROUP_WORKSPACE/profile.tsv" \
        group_slug "$GROUP_SLUG" \
        name "$GROUP_NAME"
    fi

    if [ ! -f "$GROUP_WORKSPACE/members.tsv" ] || [ -n "$IDENTITY_KEY" ]; then
      append_unique_tsv_line "$GROUP_WORKSPACE/members.tsv" \
        "$(printf '%s\t%s\t%s\t%s\n' "$USER_SLUG" "$PLATFORM" "$USER_ID" "$IDENTITY_KEY")"
    fi
  fi

  if [ -n "$CONVERSATION_DIR" ]; then
    ensure_dir_no_symlink "$ROOT/workspace/conversations/$PLATFORM" "platform conversations"
    ensure_dir_no_symlink "$CONVERSATION_DIR" "conversation metadata"
    write_kv_file "$CONVERSATION_DIR/metadata.tsv" \
      platform "$PLATFORM" \
      chat_id "$CHAT_ID" \
      chat_segment "$CONVERSATION_SEGMENT" \
      actor_user "$USER_SLUG" \
      group_slug "$GROUP_SLUG"
  fi

  emit_exports > "$CONTEXT_FILE"
fi

emit_exports
print_export KNOT_CONTEXT_FILE "$CONTEXT_FILE"
