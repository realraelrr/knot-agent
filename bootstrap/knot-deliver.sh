#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM=""
CHAT_ID=""
USER_ID=""
SESSION_KEY=""
NAME=""
KIND=""
SOURCE_PATH=""
OUTPUT_NAME=""

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-deliver.sh --platform NAME --chat-id ID --user-id ID --kind image|file --path FILE [options]

Options:
  --root DIR          Knot root. Defaults to the parent of this script.
  --session-key KEY   Original IM session key to record in metadata.
  --name NAME         Human display name to record in metadata.
  --output-name NAME  File name to use under the session deliverables directory.
  --help, -h          Show this help.

Copies FILE into the current session deliverables directory, validates the
boundary, then prints a cc-connect attachment block.
EOF
}

die() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
}

resolve_path() {
  local path="$1"

  perl -MCwd=realpath -e '
    my $path = realpath($ARGV[0]);
    exit 1 unless defined $path;
    print "$path\n";
  ' "$path"
}

absolute_path() {
  local path="$1"

  perl -MCwd=getcwd -MFile::Spec -e '
    my $path = File::Spec->rel2abs($ARGV[0], getcwd());
    $path = File::Spec->canonpath($path);
    print "$path\n";
  ' "$path"
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
    --kind)
      shift
      [ "$#" -gt 0 ] || die "--kind requires a value"
      KIND="$1"
      ;;
    --path)
      shift
      [ "$#" -gt 0 ] || die "--path requires a value"
      SOURCE_PATH="$1"
      ;;
    --output-name)
      shift
      [ "$#" -gt 0 ] || die "--output-name requires a value"
      OUTPUT_NAME="$1"
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
[ -n "$KIND" ] || die "--kind is required"
[ -n "$SOURCE_PATH" ] || die "--path is required"

case "$KIND" in
  image|file)
    ;;
  *)
    die "--kind must be image or file"
    ;;
esac

[ -f "$SOURCE_PATH" ] || die "file not found: $SOURCE_PATH"

ROOT="$(cd "$ROOT" && pwd)"
SOURCE_ABS="$(resolve_path "$SOURCE_PATH")" || die "cannot resolve file path: $SOURCE_PATH"
SOURCE_TEXT_ABS="$(absolute_path "$SOURCE_PATH")"
SESSION_ARGS=(--root "$ROOT" --platform "$PLATFORM" --chat-id "$CHAT_ID" --user-id "$USER_ID")
[ -z "$SESSION_KEY" ] || SESSION_ARGS+=(--session-key "$SESSION_KEY")
[ -z "$NAME" ] || SESSION_ARGS+=(--name "$NAME")
SESSION_DIR="$(bash "$SCRIPT_DIR/knot-session.sh" "${SESSION_ARGS[@]}")"
DELIVERABLES_DIR="$(resolve_path "$SESSION_DIR/deliverables")" || die "cannot resolve deliverables directory"
SESSION_REAL="$(resolve_path "$SESSION_DIR")" || die "cannot resolve session directory"
SESSION_TEXT_ABS="$(absolute_path "$SESSION_DIR")"
SESSIONS_DIR="$(resolve_path "$ROOT/workspace/sessions")" || die "cannot resolve sessions directory"

SESSION_MARKER="/workspace/sessions/"
CURRENT_SESSION_SUFFIX="${SESSION_TEXT_ABS#*"$SESSION_MARKER"}"
case "$SOURCE_TEXT_ABS" in
  *"$SESSION_MARKER"*)
    SOURCE_SESSION_SUFFIX="${SOURCE_TEXT_ABS#*"$SESSION_MARKER"}"
    case "$SOURCE_SESSION_SUFFIX" in
      "$CURRENT_SESSION_SUFFIX"/*)
        case "$SOURCE_ABS" in
          "$SESSION_REAL"/*)
            ;;
          *)
            die "source path in current IM session resolves outside it"
            ;;
        esac
        ;;
      *)
        die "source file belongs to another IM session"
        ;;
    esac
    ;;
esac

case "$SOURCE_ABS" in
  "$SESSIONS_DIR"/*)
    case "$SOURCE_ABS" in
      "$SESSION_REAL"/*)
        ;;
      *)
        die "source file belongs to another IM session"
        ;;
    esac
    ;;
esac

if [ -z "$OUTPUT_NAME" ]; then
  OUTPUT_NAME="$(basename "$SOURCE_ABS")"
fi

case "$OUTPUT_NAME" in
  ""|"."|".."|*$'\n'*|*/*)
    die "--output-name must be a single file name"
    ;;
esac

case "$SOURCE_ABS" in
  "$DELIVERABLES_DIR"/*)
    DEST_PATH="$SOURCE_ABS"
    ;;
  *)
    DEST_PATH="$(unique_path "$DELIVERABLES_DIR" "$OUTPUT_NAME")"
    cp -p "$SOURCE_ABS" "$DEST_PATH"
    ;;
esac

bash "$SCRIPT_DIR/knot-attachment.sh" \
  --root "$ROOT" \
  --platform "$PLATFORM" \
  --chat-id "$CHAT_ID" \
  --user-id "$USER_ID" \
  --kind "$KIND" \
  --path "$DEST_PATH"
