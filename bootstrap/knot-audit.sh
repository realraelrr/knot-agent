#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"

COMMAND="${1:-}"
[ "$#" -eq 0 ] || shift

CONVERSATION_DIR="${KNOT_CONVERSATION_DIR:-}"
EVENT=""
PLATFORM="${KNOT_PLATFORM:-}"
CHAT_ID=""
CHAT_ID_HASH="${KNOT_CHAT_ID_HASH:-}"
USER_ID=""
USER_ID_HASH="${KNOT_PLATFORM_USER_ID_HASH:-}"
IDENTITY_KEY=""
IDENTITY_KEY_HASH="${KNOT_IDENTITY_KEY_HASH:-}"
ACTOR_USER="${KNOT_ACTOR_USER:-}"
GROUP_SLUG="${KNOT_GROUP_SLUG:-${KNOT_SOURCE_GROUP:-}}"
CODEX_SESSION_ID="${KNOT_CODEX_SESSION_ID:-}"
STATUS=""
REASON_CODE=""
RESOURCE_KIND=""
RESOURCE_PATH=""

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-audit.sh record --event NAME --platform NAME --conversation-dir DIR [options]

Options:
  --root DIR
  --conversation-dir DIR
  --event NAME
  --platform NAME
  --chat-id ID | --chat-id-hash sha256:HEX
  --user-id ID | --user-id-hash sha256:HEX | --platform-user-id-hash sha256:HEX
  --identity-key KEY | --identity-key-hash sha256:HEX
  --actor-user SLUG
  --group-slug SLUG
  --codex-session-id ID
  --status allowed|denied|recorded|sent|failed|completed
  --reason-code CODE
  --resource-kind image|file
  --resource-path FILE
EOF
}

validate_hash() {
  local label="$1"
  local value="$2"

  [ -z "$value" ] && return 0
  if ! printf '%s' "$value" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
    die "$label must match sha256:<64 lowercase hex chars>"
  fi
}

hash_or_existing() {
  local raw="$1"
  local existing="$2"
  local mode="${3:-string}"

  if [ -n "$raw" ]; then
    if [ "$mode" = "platform-chat" ]; then
      printf 'sha256:%s\n' "$(sha256_hex_pair "$PLATFORM" "$raw")"
    else
      printf 'sha256:%s\n' "$(sha256_hex_string "$raw")"
    fi
    return
  fi
  [ -n "$existing" ] || return 0
  validate_hash "hash" "$existing"
  printf '%s\n' "$existing"
}

validate_reason_code() {
  local code="$1"

  case "$code" in
    ""|already_initialized|conversation_context_missing|outside_deliverables|conversation_source_denied|unauthorized_group|symlink_denied|invalid_resource|send_failed|recovery_empty|write_failed)
      ;;
    *)
      die "unsupported reason code: $code"
      ;;
  esac
}

validate_event() {
  case "$EVENT" in
    conversation.initialized|input.ref.recorded|group.access.allowed|group.access.denied|delivery.verified|delivery.denied|delivery.sent|delivery.failed|recovery.prompt_sent|recovery.completed|recovery.failed)
      ;;
    *)
      die "unsupported audit event: $EVENT"
      ;;
  esac
}

relative_resource_path() {
  local path="$1"
  local abs

  [ -n "$path" ] || return 0
  if abs="$(resolve_path "$path" 2>/dev/null)"; then
    case "$abs" in
      "$ROOT_REAL"/*)
        printf '%s\n' "${abs#"$ROOT_REAL/"}"
        ;;
      *)
        printf '%s\n' "$abs"
        ;;
    esac
    return
  fi

  if abs="$(absolute_path "$path" 2>/dev/null)"; then
    case "$abs" in
      "$ROOT_REAL"/*)
        printf '%s\n' "${abs#"$ROOT_REAL/"}"
        ;;
      *)
        printf '%s\n' "$abs"
        ;;
    esac
  else
    printf '%s\n' "$path"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      ROOT="$1"
      ;;
    --conversation-dir)
      shift
      [ "$#" -gt 0 ] || die "--conversation-dir requires a value"
      CONVERSATION_DIR="$1"
      ;;
    --event)
      shift
      [ "$#" -gt 0 ] || die "--event requires a value"
      EVENT="$1"
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
    --chat-id-hash)
      shift
      [ "$#" -gt 0 ] || die "--chat-id-hash requires a value"
      CHAT_ID_HASH="$1"
      ;;
    --user-id)
      shift
      [ "$#" -gt 0 ] || die "--user-id requires a value"
      USER_ID="$1"
      ;;
    --user-id-hash|--platform-user-id-hash)
      option="$1"
      shift
      [ "$#" -gt 0 ] || die "$option requires a value"
      USER_ID_HASH="$1"
      ;;
    --identity-key)
      shift
      [ "$#" -gt 0 ] || die "--identity-key requires a value"
      IDENTITY_KEY="$1"
      ;;
    --identity-key-hash)
      shift
      [ "$#" -gt 0 ] || die "--identity-key-hash requires a value"
      IDENTITY_KEY_HASH="$1"
      ;;
    --actor-user)
      shift
      [ "$#" -gt 0 ] || die "--actor-user requires a value"
      ACTOR_USER="$1"
      ;;
    --group-slug)
      shift
      [ "$#" -gt 0 ] || die "--group-slug requires a value"
      GROUP_SLUG="$1"
      ;;
    --codex-session-id)
      shift
      [ "$#" -gt 0 ] || die "--codex-session-id requires a value"
      CODEX_SESSION_ID="$1"
      ;;
    --status)
      shift
      [ "$#" -gt 0 ] || die "--status requires a value"
      STATUS="$1"
      ;;
    --reason-code)
      shift
      [ "$#" -gt 0 ] || die "--reason-code requires a value"
      REASON_CODE="$1"
      ;;
    --resource-kind)
      shift
      [ "$#" -gt 0 ] || die "--resource-kind requires a value"
      RESOURCE_KIND="$1"
      ;;
    --resource-path)
      shift
      [ "$#" -gt 0 ] || die "--resource-path requires a value"
      RESOURCE_PATH="$1"
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

[ "$COMMAND" = "record" ] || die "first argument must be record"
[ -n "$EVENT" ] || die "--event is required"
[ -n "$PLATFORM" ] || die "--platform is required"
[ -n "$CONVERSATION_DIR" ] || die "--conversation-dir or KNOT_CONVERSATION_DIR is required"
[ -n "$STATUS" ] || die "--status is required"

validate_event
validate_reason_code "$REASON_CODE"

ROOT="$(cd "$ROOT" && pwd)"
ROOT_REAL="$(absolute_path "$ROOT")" || die "cannot resolve Knot root"
CONVERSATIONS_ROOT="$(absolute_path "$ROOT/workspace/conversations")" || die "cannot resolve conversations root"
CONVERSATION_DIR="$(absolute_path "$CONVERSATION_DIR")" || die "cannot resolve conversation directory location"

case "$CONVERSATION_DIR" in
  "$CONVERSATIONS_ROOT"/*)
    ;;
  *)
    die "conversation directory must be under workspace/conversations"
    ;;
esac

platform_dir="$(dirname "$CONVERSATION_DIR")"
platform_segment="$(basename "$platform_dir")"
chat_segment="$(basename "$CONVERSATION_DIR")"

[ "$platform_segment" = "$PLATFORM" ] || die "conversation platform directory does not match event platform"
if ! printf '%s' "$chat_segment" | grep -Eq '^chat_[0-9a-f]{24}$'; then
  die "conversation directory must use chat_<hash> segment"
fi

CHAT_ID_HASH="$(hash_or_existing "$CHAT_ID" "$CHAT_ID_HASH" platform-chat)"
[ -n "$CHAT_ID_HASH" ] || die "--chat-id or --chat-id-hash is required"
expected_segment="chat_${CHAT_ID_HASH#sha256:}"
expected_segment="${expected_segment:0:29}"
[ "$chat_segment" = "$expected_segment" ] || die "conversation directory does not match chat hash"

USER_ID_HASH="$(hash_or_existing "$USER_ID" "$USER_ID_HASH")"
IDENTITY_KEY_HASH="$(hash_or_existing "$IDENTITY_KEY" "$IDENTITY_KEY_HASH")"

ensure_dir_no_symlink "$CONVERSATIONS_ROOT" "conversations root"
ensure_dir_no_symlink "$platform_dir" "platform conversations"
ensure_dir_no_symlink "$CONVERSATION_DIR" "conversation audit directory"

resource_path=""
resource_sha256=""
resource_size_bytes=0
if [ -n "$RESOURCE_PATH" ]; then
  resource_path="$(relative_resource_path "$RESOURCE_PATH")"
  if [ -f "$RESOURCE_PATH" ]; then
    resource_sha256="$(file_sha256 "$RESOURCE_PATH")"
    resource_size_bytes="$(file_size_bytes "$RESOURCE_PATH")"
  fi
fi

printf '{"schema_version":"0.1","time":"%s","event":"%s","platform":"%s","chat_id_hash":"%s","platform_user_id_hash":"%s","identity_key_hash":"%s","actor_user":"%s","group_slug":"%s","codex_session_id":"%s","status":"%s","reason_code":"%s","resource_kind":"%s","resource_path":"%s","resource_sha256":"%s","resource_size_bytes":%s}\n' \
  "$(timestamp_utc)" \
  "$(json_escape "$EVENT")" \
  "$(json_escape "$PLATFORM")" \
  "$(json_escape "$CHAT_ID_HASH")" \
  "$(json_escape "$USER_ID_HASH")" \
  "$(json_escape "$IDENTITY_KEY_HASH")" \
  "$(json_escape "$ACTOR_USER")" \
  "$(json_escape "$GROUP_SLUG")" \
  "$(json_escape "$CODEX_SESSION_ID")" \
  "$(json_escape "$STATUS")" \
  "$(json_escape "$REASON_CODE")" \
  "$(json_escape "$RESOURCE_KIND")" \
  "$(json_escape "$resource_path")" \
  "$(json_escape "$resource_sha256")" \
  "$resource_size_bytes" >> "$CONVERSATION_DIR/events.jsonl"
