#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM=""
FAILURES=0
ENV_KEYS=""

ok() { printf 'OK   %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; }
fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-runtime-check.sh --platform NAME [--root DIR]

Platform names: dingtalk, feishu, wecom, weixin

Checks only local runtime readiness: files, executability, .env variables,
KNOT_ROOT, writability, and basic platform config matching. It does not start
the gateway, call /whoami, or verify live IM authorization.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform)
      shift
      if [ "$#" -eq 0 ]; then
        fail "--platform requires a value"
        break
      fi
      PLATFORM="$1"
      ;;
    --root)
      shift
      if [ "$#" -eq 0 ]; then
        fail "--root requires a value"
        break
      fi
      ROOT="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift
done

if [ -z "$PLATFORM" ]; then
  fail "--platform is required"
fi

ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || {
  fail "root directory does not exist: $ROOT"
  ROOT=""
}

runtime_dir_for() {
  case "$1" in
    dingtalk|feishu|wecom)
      printf '%s/runtime/dingtalk-feishu-wecom\n' "$ROOT"
      ;;
    weixin)
      printf '%s/runtime/weixin\n' "$ROOT"
      ;;
    *)
      return 1
      ;;
  esac
}

required_vars_for() {
  case "$1" in
    dingtalk)
      printf '%s\n' KNOT_ROOT DINGTALK_CLIENT_ID DINGTALK_CLIENT_SECRET DINGTALK_ROBOT_CODE DINGTALK_ALLOW_FROM
      ;;
    feishu)
      printf '%s\n' KNOT_ROOT FEISHU_APP_ID FEISHU_APP_SECRET FEISHU_ALLOW_FROM
      ;;
    wecom)
      printf '%s\n' KNOT_ROOT WECOM_BOT_ID WECOM_BOT_SECRET WECOM_ALLOW_FROM
      ;;
    weixin)
      printf '%s\n' KNOT_ROOT WEIXIN_ALLOW_FROM
      ;;
    *)
      return 1
      ;;
  esac
}

check_file() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    ok "$label: $path"
  else
    fail "$label missing: $path"
  fi
}

check_executable() {
  local path="$1"
  local label="$2"

  if [ -x "$path" ]; then
    ok "$label: $path"
  else
    fail "$label missing or not executable: $path"
  fi
}

check_nonempty_env() {
  local name="$1"
  local value

  value="$(get_env "$name")"
  if [ -n "$value" ]; then
    ok "$name is set"
  else
    fail "$name is empty or missing"
  fi
}

is_allowed_env_name() {
  case "$1" in
    KNOT_ROOT|DINGTALK_CLIENT_ID|DINGTALK_CLIENT_SECRET|DINGTALK_ROBOT_CODE|DINGTALK_ALLOW_FROM|FEISHU_APP_ID|FEISHU_APP_SECRET|FEISHU_ALLOW_FROM|FEISHU_ALLOW_CHAT|WECOM_BOT_ID|WECOM_BOT_SECRET|WECOM_ALLOW_FROM|WEIXIN_ALLOW_FROM)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

set_env_value() {
  local key="$1"
  local value="$2"
  local encoded

  encoded="$(printf '%s' "$value" | base64 | tr -d '\n')"
  eval "ENV_$key=\$encoded"
  case " $ENV_KEYS " in
    *" $key "*)
      ;;
    *)
      ENV_KEYS="${ENV_KEYS}${ENV_KEYS:+ }$key"
      ;;
  esac
}

get_env() {
  local key="$1"
  local encoded

  eval "encoded=\${ENV_$key:-}"
  if [ -z "$encoded" ]; then
    return 0
  fi
  printf '%s' "$encoded" | base64 --decode
}

parse_env_file() {
  local path="$1"
  local line
  local key
  local value

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    case "$line" in
      ""|\#*)
        continue
        ;;
      export\ *)
        line="${line#export }"
        ;;
    esac

    case "$line" in
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        ;;
      *)
        warn ".env ignored non-assignment line"
        continue
        ;;
    esac

    if ! printf '%s\n' "$key" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
      warn ".env ignored invalid key: $key"
      continue
    fi

    if [ "$key" = "KNOT_ACTIVE_WORKSPACE" ]; then
      fail ".env must not set KNOT_ACTIVE_WORKSPACE; Knot resolves it per message"
      continue
    fi

    if ! is_allowed_env_name "$key"; then
      continue
    fi

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
      \"*\")
        value="${value#\"}"
        value="${value%\"}"
        ;;
      \'*\')
        value="${value#\'}"
        value="${value%\'}"
        ;;
    esac

    set_env_value "$key" "$value"
  done < "$path"
}

config_has_kv() {
  local path="$1"
  local key="$2"
  local value="$3"

  grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*[\"']${value}[\"'][[:space:]]*($|#)" "$path"
}

config_has_key() {
  local path="$1"
  local key="$2"

  grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$path"
}

config_has_bool_true() {
  local path="$1"
  local key="$2"

  grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*true[[:space:]]*($|#)" "$path"
}

config_value_for() {
  local path="$1"
  local key="$2"
  local line
  local value

  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$path" | head -1)" || return 0
  value="${line#*=}"
  value="${value%%#*}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  case "$value" in
    \"*\")
      value="${value#\"}"
      value="${value%\"}"
      ;;
    \'*\')
      value="${value#\'}"
      value="${value%\'}"
      ;;
  esac
  printf '%s\n' "$value"
}

case "$PLATFORM" in
  dingtalk|feishu|wecom|weixin)
    ;;
  "")
    ;;
  *)
    fail "unknown platform: $PLATFORM"
    ;;
esac

if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi

RUNTIME_DIR="$(runtime_dir_for "$PLATFORM")" || {
  fail "unknown platform: $PLATFORM"
  exit 1
}
CONFIG_FILE="$RUNTIME_DIR/config.$PLATFORM.toml"
RUN_SCRIPT="$RUNTIME_DIR/run-$PLATFORM.sh"
ENV_FILE="$RUNTIME_DIR/.env"
BINARY="$RUNTIME_DIR/bin/cc-connect"

printf 'Knot runtime check\n'
printf 'Root: %s\n' "$ROOT"
printf 'Platform: %s\n\n' "$PLATFORM"

if [ -d "$RUNTIME_DIR" ]; then
  ok "runtime directory: $RUNTIME_DIR"
else
  fail "runtime directory missing: $RUNTIME_DIR"
fi

if [ -w "$RUNTIME_DIR" ]; then
  ok "runtime directory writable"
else
  fail "runtime directory is not writable: $RUNTIME_DIR"
fi

check_executable "$BINARY" "cc-connect binary"
check_file "$CONFIG_FILE" "platform config"
check_executable "$RUN_SCRIPT" "run script"
check_file "$ENV_FILE" ".env"

if [ -f "$ENV_FILE" ]; then
  parse_env_file "$ENV_FILE"
fi

for var_name in $(required_vars_for "$PLATFORM"); do
  check_nonempty_env "$var_name"
done

KNOT_ROOT_VALUE="$(get_env KNOT_ROOT)"
if [ -n "$KNOT_ROOT_VALUE" ]; then
  RESOLVED_KNOT_ROOT="$(cd "$KNOT_ROOT_VALUE" 2>/dev/null && pwd)" || RESOLVED_KNOT_ROOT=""
  if [ "$RESOLVED_KNOT_ROOT" = "$ROOT" ]; then
    ok "KNOT_ROOT points to current root"
  else
    fail "KNOT_ROOT does not point to current root: $KNOT_ROOT_VALUE"
  fi
fi

if [ -f "$CONFIG_FILE" ]; then
  if config_has_kv "$CONFIG_FILE" "type" "$PLATFORM"; then
    ok "config platform type matches $PLATFORM"
  else
    fail "config missing platform type: type = \"$PLATFORM\""
  fi

  # The config should contain literal ${KNOT_ROOT} placeholders for runtime expansion.
  # shellcheck disable=SC2016
  if grep -Eq '^[[:space:]]*\[projects\.knot_workspace\][[:space:]]*$' "$CONFIG_FILE" &&
    config_has_bool_true "$CONFIG_FILE" "enabled" &&
    grep -Fq 'helper = "${KNOT_ROOT}/bootstrap/knot-workspace.sh"' "$CONFIG_FILE" &&
    grep -Fq 'root = "${KNOT_ROOT}"' "$CONFIG_FILE"; then
    ok "config enables Knot per-message workspace resolver"
  else
    fail "config missing [projects.knot_workspace] resolver for per-message workspaces"
  fi

  WORK_DIR_VALUE="$(config_value_for "$CONFIG_FILE" "work_dir")"
  if config_has_key "$CONFIG_FILE" "work_dir"; then
    fail "config must not use static agent work_dir with Knot workspace resolver: $WORK_DIR_VALUE"
  else
    ok "config does not pin a static agent work_dir"
  fi
fi

if [ "$PLATFORM" = "feishu" ] && [ -z "$(get_env FEISHU_ALLOW_CHAT)" ]; then
  warn "FEISHU_ALLOW_CHAT is empty; this is acceptable for direct-chat-only setups"
fi

printf '\nDone.\n'

if [ "$FAILURES" -gt 0 ]; then
  printf 'FAILED %s required check(s).\n' "$FAILURES"
  exit 1
fi
