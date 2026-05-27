#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/knot/core.sh
. "$ROOT/lib/knot/core.sh"
PLATFORM=""
CHAT_ID=""
USER_ID=""
USER_SLUG=""
GROUP_SLUG=""
IDENTITY_KEY=""
NAME=""
GROUP_NAME=""
CREATE_DIRS=1
EMIT_CONVERSATION_INITIALIZED=0

usage() {
  cat <<'EOF'
Usage: bash bin/knot-workspace.sh --platform NAME --user-id ID [options]

Options:
  --root DIR           Knot root. Defaults to the parent of this script.
  --chat-id ID         Source chat id for conversation audit metadata.
  --user-slug SLUG     Current user workspace slug under workspace/users/.
  --group-slug SLUG    Current group workspace slug for group chats.
  --identity-key KEY   Stable identity/context key from the IM glue layer.
  --name NAME          Human display name to record in metadata.
  --group-name NAME    Human group display name to record in metadata.
  --no-create          Resolve paths and print exports without creating files.
  --emit-conversation-initialized
                       Emit one audit event when a new conversation dir is created.
  --help, -h           Show this help.

If --user-slug or --group-slug is omitted for IM/runtime routing, this helper
must resolve a unique row from workspace/admin/permissions.md. Explicit slugs
remain supported for local CLI and scaffold smoke paths.

Prints source-safe shell exports. The caller should start Codex with cwd set to
KNOT_ACTIVE_WORKSPACE.
EOF
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
  print_export KNOT_SCOPE "$KNOT_SCOPE"
  print_export KNOT_ACTIVE_WORKSPACE "$ACTIVE_WORKSPACE"
  print_export KNOT_SCOPE_WORKSPACE "$SCOPE_WORKSPACE"
  print_export KNOT_ACTOR_WORKSPACE "$ACTOR_WORKSPACE"
  print_export KNOT_USER_WORKSPACE "$USER_WORKSPACE"
  print_export KNOT_GROUP_WORKSPACE "$GROUP_WORKSPACE"
  print_export KNOT_CONVERSATION_DIR "$CONVERSATION_DIR"
  print_export KNOT_ACTOR_USER "$USER_SLUG"
  print_export KNOT_SOURCE_GROUP "$GROUP_SLUG"
  print_export KNOT_GROUP_SLUG "$GROUP_SLUG"
  print_export KNOT_PLATFORM "$PLATFORM"
  print_export KNOT_PLATFORM_USER_ID "$USER_ID"
  print_export KNOT_CHAT_ID "$CHAT_ID"
  print_export KNOT_IDENTITY_KEY "$IDENTITY_KEY"
  print_export KNOT_CHAT_ID_HASH "$CHAT_ID_HASH"
  print_export KNOT_PLATFORM_USER_ID_HASH "$PLATFORM_USER_ID_HASH"
  print_export KNOT_IDENTITY_KEY_HASH "$IDENTITY_KEY_HASH"
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

deny_routing() {
  local message="$1"

  if [ "$CREATE_DIRS" -eq 1 ] && [ -n "$CONVERSATION_DIR" ]; then
    ensure_dir_no_symlink "$ROOT/workspace" "workspace root"
    ensure_dir_no_symlink "$ROOT/workspace/conversations" "conversations root"
    ensure_dir_no_symlink "$ROOT/workspace/conversations/$PLATFORM" "platform conversations"
    ensure_dir_no_symlink "$CONVERSATION_DIR" "conversation audit directory"
    if ! bash "$SCRIPT_DIR/knot-audit.sh" record \
      --root "$ROOT" \
      --conversation-dir "$CONVERSATION_DIR" \
      --event group.access.denied \
      --platform "$PLATFORM" \
      --chat-id-hash "$CHAT_ID_HASH" \
      --user-id-hash "$PLATFORM_USER_ID_HASH" \
      --identity-key-hash "$IDENTITY_KEY_HASH" \
      --actor-user "$USER_SLUG" \
      --group-slug "$GROUP_SLUG" \
      --status denied \
      --reason-code unauthorized_group; then
      die "workspace routing denied but audit event could not be recorded: $message"
    fi
  fi
  die "$message"
}

routing_unique_or_empty() {
  local label="$1"
  local values="$2"
  local required="${3:-0}"
  local count

  count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  case "$count" in
    0)
      [ "$required" -eq 0 ] && return 0
      deny_routing "$label is not uniquely mapped in workspace/admin/permissions.md"
      ;;
    1)
      printf '%s\n' "$values" | sed '/^$/d' | head -n 1
      ;;
    *)
      deny_routing "$label maps to multiple values in workspace/admin/permissions.md"
      ;;
  esac
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
    --emit-conversation-initialized)
      EMIT_CONVERSATION_INITIALIZED=1
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
PERMISSIONS_FILE="$ROOT/workspace/admin/permissions.md"
CONVERSATION_DIR=""
CONVERSATION_SEGMENT=""
CHAT_ID_HASH=""
PLATFORM_USER_ID_HASH="sha256:$(sha256_hex_string "$USER_ID")"
IDENTITY_KEY_HASH=""

if [ -n "$CHAT_ID" ]; then
  CHAT_ID_HASH="sha256:$(sha256_hex_pair "$PLATFORM" "$CHAT_ID")"
  CONVERSATION_SEGMENT="chat_${CHAT_ID_HASH#sha256:}"
  CONVERSATION_SEGMENT="${CONVERSATION_SEGMENT:0:29}"
  CONVERSATION_DIR="$ROOT/workspace/conversations/$PLATFORM/$CONVERSATION_SEGMENT"
fi
if [ -n "$IDENTITY_KEY" ]; then
  IDENTITY_KEY_HASH="sha256:$(sha256_hex_string "$IDENTITY_KEY")"
fi

if [ -f "$PERMISSIONS_FILE" ]; then
  RESOLVED_USER_SLUG="$(routing_unique_or_empty \
    "actor identity" \
    "$(permissions_actor_workspaces "$ROOT" "$PLATFORM" "$USER_ID" "$IDENTITY_KEY")" \
    1)"
  if [ -z "$USER_SLUG" ]; then
    USER_SLUG="$RESOLVED_USER_SLUG"
  elif [ "$USER_SLUG" != "$RESOLVED_USER_SLUG" ]; then
    deny_routing "actor identity resolves to $RESOLVED_USER_SLUG, not --user-slug $USER_SLUG"
  fi
elif [ -z "$USER_SLUG" ]; then
  die "--user-slug is required when workspace/admin/permissions.md is missing"
fi

if [ -z "$GROUP_SLUG" ] && [ -n "$CHAT_ID" ] && [ -f "$PERMISSIONS_FILE" ]; then
  GROUP_SLUG="$(routing_unique_or_empty \
    "group context" \
    "$(permissions_groups_for_actor_chat "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY")" \
    0)"
fi

validate_slug "--user-slug" "$USER_SLUG"
[ -z "$GROUP_SLUG" ] || validate_slug "--group-slug" "$GROUP_SLUG"

if [ -n "$GROUP_SLUG" ] && [ -f "$PERMISSIONS_FILE" ] && ! permissions_group_authorized "$ROOT" "$PLATFORM" "$USER_ID" "$CHAT_ID" "$IDENTITY_KEY" "$GROUP_SLUG"; then
  deny_routing "group workspace is not authorized for this actor/context: $GROUP_SLUG"
fi

USER_WORKSPACE="$(knot_scope_user_workspace "$ROOT" "$USER_SLUG")"
GROUP_WORKSPACE=""
KNOT_SCOPE="direct"
SCOPE_WORKSPACE="$USER_WORKSPACE"
ACTIVE_WORKSPACE="$USER_WORKSPACE"
ACTOR_WORKSPACE="$USER_WORKSPACE"

if [ -n "$GROUP_SLUG" ]; then
  GROUP_WORKSPACE="$(knot_scope_group_workspace "$ROOT" "$GROUP_SLUG")"
  KNOT_SCOPE="group"
  SCOPE_WORKSPACE="$GROUP_WORKSPACE"
  ACTIVE_WORKSPACE="$GROUP_WORKSPACE"
  ACTOR_WORKSPACE="$(knot_scope_actor_workspace "$ROOT" group "$USER_SLUG" "$GROUP_SLUG")"
fi

CONTEXT_DIR="$ACTOR_WORKSPACE/.knot"
CONTEXT_FILE="$CONTEXT_DIR/current-context.sh"

if [ -L "$USER_WORKSPACE" ]; then
  die "user workspace must not be a symlink: $USER_WORKSPACE"
fi

if [ -n "$GROUP_WORKSPACE" ] && [ -L "$GROUP_WORKSPACE" ]; then
  die "group workspace must not be a symlink: $GROUP_WORKSPACE"
fi

CONVERSATION_EXISTED=0
if [ -n "$CONVERSATION_DIR" ] && [ -d "$CONVERSATION_DIR" ]; then
  CONVERSATION_EXISTED=1
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
  if [ "$KNOT_SCOPE" = "direct" ]; then
    ensure_dir_no_symlink "$CONTEXT_DIR" "user context"
  fi

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
    ensure_dir_no_symlink "$ACTOR_WORKSPACE" "group actor workspace"
    ensure_dir_no_symlink "$ACTOR_WORKSPACE/inbox" "group actor inbox"
    ensure_dir_no_symlink "$ACTOR_WORKSPACE/.state" "group actor state"
    ensure_dir_no_symlink "$ACTOR_WORKSPACE/.state/tasks" "group actor task state"
    ensure_dir_no_symlink "$CONTEXT_DIR" "group actor context"

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
    if [ "$EMIT_CONVERSATION_INITIALIZED" -eq 1 ] && [ "$CONVERSATION_EXISTED" -eq 0 ]; then
      bash "$SCRIPT_DIR/knot-audit.sh" record \
        --root "$ROOT" \
        --conversation-dir "$CONVERSATION_DIR" \
        --event conversation.initialized \
        --platform "$PLATFORM" \
        --chat-id-hash "$CHAT_ID_HASH" \
        --user-id-hash "$PLATFORM_USER_ID_HASH" \
        --identity-key-hash "$IDENTITY_KEY_HASH" \
        --actor-user "$USER_SLUG" \
        --group-slug "$GROUP_SLUG" \
        --status allowed
    fi
  fi

  emit_exports > "$CONTEXT_FILE"
fi

emit_exports
print_export KNOT_CONTEXT_FILE "$CONTEXT_FILE"
