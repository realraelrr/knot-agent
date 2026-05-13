#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM=""
CHAT_ID=""
USER_ID=""
SESSION_KEY=""
NAME=""
WRITE_METADATA=1

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-session.sh --platform NAME --chat-id ID --user-id ID [options]

Options:
  --root DIR          Knot root. Defaults to the parent of this script.
  --session-key KEY   Original IM session key to record in metadata.
  --name NAME         Human display name to record in metadata.
  --no-metadata       Create directories only; do not write session.tsv.
  --help, -h          Show this help.

Creates and prints:
  workspace/sessions/<platform>/<chat_id>/<user_id>
EOF
}

die() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
}

hash_value() {
  printf '%s' "$1" | shasum -a 256 | awk '{print substr($1, 1, 12)}'
}

safe_id_segment() {
  local raw="$1"
  local safe
  local hash

  safe="$(printf '%s' "$raw" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_' | sed 's/^_*//; s/_*$//; s/__*/_/g' | cut -c 1-80)"
  if [ -z "$safe" ]; then
    safe="id"
  fi

  hash="$(hash_value "$raw")"
  printf '%s-%s\n' "$safe" "$hash"
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
    --session-key)
      shift
      [ "$#" -gt 0 ] || die "--session-key requires a value"
      SESSION_KEY="$1"
      ;;
    --name)
      shift
      [ "$#" -gt 0 ] || die "--name requires a value"
      NAME="$1"
      ;;
    --no-metadata)
      WRITE_METADATA=0
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
[ -n "$CHAT_ID" ] || die "--chat-id is required"
[ -n "$USER_ID" ] || die "--user-id is required"

case "$PLATFORM" in
  dingtalk|feishu|wecom|weixin)
    ;;
  *)
    die "unsupported platform: $PLATFORM"
    ;;
esac

ROOT="$(cd "$ROOT" && pwd)"
CHAT_SEGMENT="$(safe_id_segment "$CHAT_ID")"
USER_SEGMENT="$(safe_id_segment "$USER_ID")"
SESSION_DIR="$ROOT/workspace/sessions/$PLATFORM/$CHAT_SEGMENT/$USER_SEGMENT"

mkdir -p \
  "$SESSION_DIR/inbox" \
  "$SESSION_DIR/work" \
  "$SESSION_DIR/deliverables" \
  "$SESSION_DIR/.state/tasks"

if [ "$WRITE_METADATA" -eq 1 ]; then
  if [ -f "$SESSION_DIR/session.tsv" ] && [ -z "$SESSION_KEY" ] && [ -z "$NAME" ]; then
    :
  else
    {
      printf 'platform\t%s\n' "$PLATFORM"
      printf 'chat_id\t%s\n' "$CHAT_ID"
      printf 'user_id\t%s\n' "$USER_ID"
      printf 'session_key\t%s\n' "$SESSION_KEY"
      printf 'name\t%s\n' "$NAME"
    } > "$SESSION_DIR/session.tsv"
  fi
fi

printf '%s\n' "$SESSION_DIR"
