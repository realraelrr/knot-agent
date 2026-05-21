# shellcheck shell=bash

die() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
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

# Call as parse_knot_context_arg "$@". The shifts below only affect this
# function's argument copy; callers consume their "$@" via KNOT_ARG_CONSUMED.
parse_knot_context_arg() {
  local arg="$1"
  local value

  KNOT_ARG_CONSUMED=0
  case "$arg" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      value="$1"
      ROOT="$value"
      EXPLICIT_CONTEXT=1
      KNOT_ARG_CONSUMED=2
      ;;
    --platform)
      shift
      [ "$#" -gt 0 ] || die "--platform requires a value"
      value="$1"
      PLATFORM="$value"
      EXPLICIT_CONTEXT=1
      KNOT_ARG_CONSUMED=2
      ;;
    --chat-id)
      shift
      [ "$#" -gt 0 ] || die "--chat-id requires a value"
      value="$1"
      CHAT_ID="$value"
      EXPLICIT_CONTEXT=1
      KNOT_ARG_CONSUMED=2
      ;;
    --user-id)
      shift
      [ "$#" -gt 0 ] || die "--user-id requires a value"
      value="$1"
      USER_ID="$value"
      EXPLICIT_CONTEXT=1
      KNOT_ARG_CONSUMED=2
      ;;
    --user-slug)
      shift
      [ "$#" -gt 0 ] || die "--user-slug requires a value"
      value="$1"
      USER_SLUG="$value"
      EXPLICIT_CONTEXT=1
      KNOT_ARG_CONSUMED=2
      ;;
    --group-slug)
      shift
      [ "$#" -gt 0 ] || die "--group-slug requires a value"
      value="$1"
      GROUP_SLUG="$value"
      EXPLICIT_CONTEXT=1
      KNOT_ARG_CONSUMED=2
      ;;
    --identity-key)
      shift
      [ "$#" -gt 0 ] || die "--identity-key requires a value"
      value="$1"
      IDENTITY_KEY="$value"
      EXPLICIT_IDENTITY_KEY=1
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

clear_implicit_identity_key() {
  if [ "${EXPLICIT_CONTEXT:-0}" -eq 1 ] && [ "${EXPLICIT_IDENTITY_KEY:-0}" -eq 0 ]; then
    IDENTITY_KEY=""
  fi
}

require_knot_context() {
  [ -n "$PLATFORM" ] || die "--platform is required"
  [ -n "$USER_ID" ] || die "--user-id is required"
  [ -n "$USER_SLUG" ] || die "--user-slug is required"
}

permissions_group_authorized() {
  local root="$1"
  local platform="$2"
  local user_id="$3"
  local chat_id="$4"
  local identity_key="$5"
  local group_slug="$6"
  local permissions_file="$root/workspace/admin/permissions.md"

  [ -n "$group_slug" ] || return 0
  [ -n "$chat_id" ] || return 1
  [ -f "$permissions_file" ] || return 1

  awk -F'|' \
    -v platform="$platform" \
    -v user_id="$user_id" \
    -v chat_id="$chat_id" \
    -v identity_key="$identity_key" \
    -v group_slug="$group_slug" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    NR < 3 || $0 !~ /^\|/ { next }
    {
      workspace = trim($3)
      row_platform = trim($4)
      row_user_id = trim($5)
      row_group = trim($6)
      row_chat_id = trim($7)
      row_identity_key = trim($8)

      if (workspace == "Workspace" || workspace == "---" || row_group == "") {
        next
      }

      if (identity_key != "") {
        actor_match = (row_identity_key == identity_key)
      } else {
        actor_match = (row_platform == platform && row_user_id == user_id)
      }
      chat_match = (chat_id != "" && row_chat_id == chat_id)

      if (row_platform == platform && row_group == group_slug && chat_match && actor_match) {
        found = 1
        exit
      }
    }
    END { exit found ? 0 : 1 }
  ' "$permissions_file"
}
