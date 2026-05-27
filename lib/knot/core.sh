# shellcheck shell=bash

KNOT_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOT_COMMAND_ROOT="$(cd "$KNOT_CORE_DIR/../.." && pwd)"

die() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
}

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

sha256_hex_string() {
  local value="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$value" | shasum -a 256 | awk '{print $1}'
    return
  fi
  die "sha256sum or shasum is required"
}

sha256_hex_pair() {
  local left="$1"
  local right="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    { printf '%s' "$left"; printf '\0'; printf '%s' "$right"; } | sha256sum | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    { printf '%s' "$left"; printf '\0'; printf '%s' "$right"; } | shasum -a 256 | awk '{print $1}'
    return
  fi
  die "sha256sum or shasum is required"
}

file_sha256() {
  local path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi
  die "sha256sum or shasum is required"
}

file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

knot_audit_record() {
  [ -n "${CONVERSATION_DIR:-}" ] || return 0
  bash "$KNOT_COMMAND_ROOT/bin/knot-audit.sh" record \
    --root "$ROOT" \
    --conversation-dir "$CONVERSATION_DIR" \
    --event "$1" \
    --platform "$PLATFORM" \
    --chat-id "${CHAT_ID:-}" \
    --user-id "${USER_ID:-}" \
    --identity-key "${IDENTITY_KEY:-}" \
    --actor-user "${USER_SLUG:-}" \
    --group-slug "${GROUP_SLUG:-}" \
    --status "$2" \
    --reason-code "${3:-}" \
    --resource-kind "${4:-}" \
    --resource-path "${5:-}"
}

knot_audit_deny_delivery() {
  local reason_code="$1"
  local resource_kind="$2"
  local resource_path="$3"
  local message="$4"

  if ! knot_audit_record delivery.denied denied "$reason_code" "$resource_kind" "$resource_path"; then
    die "delivery denied but audit event could not be recorded: $message"
  fi
  die "$message"
}

knot_audit_deny_group_access() {
  local message="$1"

  if ! knot_audit_record group.access.denied denied unauthorized_group; then
    die "group access denied but audit event could not be recorded: $message"
  fi
  die "$message"
}

absolute_path() {
  local path="$1"
  local dir
  local base

  case "$path" in
    /*)
      ;;
    *)
      path="$PWD/$path"
      ;;
  esac

  dir="$(cd "$(dirname "$path")" && pwd -P)" || return 1
  base="$(basename "$path")"
  printf '%s/%s\n' "$dir" "$base"
}

resolve_path() {
  local path="$1"
  local target
  local limit=0

  path="$(absolute_path "$path")" || return 1
  while [ -L "$path" ]; do
    limit=$((limit + 1))
    [ "$limit" -le 40 ] || return 1

    target="$(readlink "$path")" || return 1
    case "$target" in
      /*)
        path="$target"
        ;;
      *)
        path="$(dirname "$path")/$target"
        ;;
    esac
    path="$(absolute_path "$path")" || return 1
  done

  [ -e "$path" ] || return 1
  absolute_path "$path"
}

resolve_symlink() {
  local path="$1"
  local target

  target="$(readlink "$path")" || return 1
  case "$target" in
    /*)
      printf '%s\n' "$target"
      ;;
    *)
      (cd "$(dirname "$path")/$target" 2>/dev/null && pwd)
      ;;
  esac
}

workspace_export() {
  local key="$1"
  local data="$2"

  printf '%s\n' "$data" | sed -n "s/^export ${key}='\\(.*\\)'$/\\1/p" | sed "s/'\\\\''/'/g" | tail -1
}

validate_slug() {
  local label="$1"
  local slug="$2"

  case "$slug" in
    ""|"."|".."|*/*|*$'\n'*)
      die "$label must be a single path segment"
      ;;
  esac

  if ! printf '%s' "$slug" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'; then
    die "$label must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$"
  fi
}

ensure_dir_no_symlink() {
  local path="$1"
  local label="$2"

  if [ -L "$path" ]; then
    die "$label must not be a symlink: $path"
  fi

  if [ -e "$path" ] && [ ! -d "$path" ]; then
    die "$label exists but is not a directory: $path"
  fi

  mkdir -p "$path"

  if [ -L "$path" ]; then
    die "$label must not be a symlink: $path"
  fi
}

shell_quote() {
  local value="$1"
  printf "'"
  printf '%s' "$value" | sed "s/'/'\\\\''/g"
  printf "'"
}

print_export() {
  local key="$1"
  local value="$2"
  printf 'export %s=' "$key"
  shell_quote "$value"
  printf '\n'
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

knot_atomic_replace() {
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

# Field-only parser; callers consume their "$@" via KNOT_ARG_CONSUMED.
# shellcheck disable=SC2034
parse_knot_context_field_arg() {
  local arg="$1"
  local value

  KNOT_ARG_CONSUMED=0
  case "$arg" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      value="$1"
      ROOT="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --platform)
      shift
      [ "$#" -gt 0 ] || die "--platform requires a value"
      value="$1"
      PLATFORM="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --chat-id)
      shift
      [ "$#" -gt 0 ] || die "--chat-id requires a value"
      value="$1"
      CHAT_ID="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --conversation-dir)
      shift
      [ "$#" -gt 0 ] || die "--conversation-dir requires a value"
      value="$1"
      CONVERSATION_DIR="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --user-id)
      shift
      [ "$#" -gt 0 ] || die "--user-id requires a value"
      value="$1"
      USER_ID="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --user-slug)
      shift
      [ "$#" -gt 0 ] || die "--user-slug requires a value"
      value="$1"
      USER_SLUG="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --group-slug)
      shift
      [ "$#" -gt 0 ] || die "--group-slug requires a value"
      value="$1"
      GROUP_SLUG="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --identity-key)
      shift
      [ "$#" -gt 0 ] || die "--identity-key requires a value"
      value="$1"
      IDENTITY_KEY="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --name)
      [ "${KNOT_PARSE_NAMES:-0}" -eq 1 ] || return 1
      shift
      [ "$#" -gt 0 ] || die "--name requires a value"
      value="$1"
      NAME="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    --group-name)
      [ "${KNOT_PARSE_NAMES:-0}" -eq 1 ] || return 1
      shift
      [ "$#" -gt 0 ] || die "--group-name requires a value"
      value="$1"
      GROUP_NAME="$value"
      KNOT_ARG_CONSUMED=2
      ;;
    *)
      return 1
      ;;
  esac
}

require_knot_context() {
  [ -n "$PLATFORM" ] || die "--platform is required"
  [ -n "$USER_ID" ] || die "--user-id is required"
  [ -n "$USER_SLUG" ] || die "--user-slug is required"
}

# shellcheck source=lib/knot/permissions.sh
. "$KNOT_CORE_DIR/permissions.sh"
# shellcheck source=lib/knot/scope.sh
. "$KNOT_CORE_DIR/scope.sh"
# shellcheck source=lib/knot/manifest.sh
. "$KNOT_CORE_DIR/manifest.sh"
