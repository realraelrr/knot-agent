#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${KNOT_ROOT:-$DEFAULT_ROOT}"
# shellcheck source=lib/knot/core.sh
. "$DEFAULT_ROOT/lib/knot/core.sh"

COMMAND="${1:-}"
[ "$#" -eq 0 ] || shift

PROFILE_PATH=""
ENFORCE_IF_FRONTMATTER=0
REQUIRE_STRUCTURED=0
ALLOWED_SECTIONS="Communication|Evidence And Review|Delivery|Recurring Workflows|Avoid"

usage() {
  cat <<'EOF'
Usage: bash bin/knot-collaborator-profile-lint.sh lint --profile FILE [options]

Options:
  --root DIR
  --profile FILE
  --enforce-if-frontmatter
  --require-structured
EOF
}

deny() {
  printf 'ERROR %s\n' "$1" >&2
  exit 1
}

profile_has_frontmatter() {
  [ "$(sed -n '1p' "$PROFILE_PATH")" = "---" ]
}

frontmatter_end_line() {
  awk 'NR > 1 && $0 == "---" { print NR; exit }' "$PROFILE_PATH"
}

validate_frontmatter() {
  local end_line="$1"
  local invalid

  invalid="$(sed -n "2,$((end_line - 1))p" "$PROFILE_PATH" |
    sed '/^[[:space:]]*$/d' |
    awk -F: '
      {
        key=$1
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        if (key !~ /^(version|updated|reviewed)$/) print key
      }' | head -1)"
  [ -z "$invalid" ] || deny "frontmatter key is not allowed: $invalid"
}

validate_sections() {
  local start_line="$1"
  local invalid

  invalid="$(tail -n +"$start_line" "$PROFILE_PATH" |
    awk -v allowed="$ALLOWED_SECTIONS" '
      BEGIN {
        title_seen = 0
        section = ""
        count = 0
      }
      /^[[:space:]]*$/ { next }
      /^# Collaborator Profile$/ {
        if (title_seen || section != "") {
          print "title must appear once before sections"
          exit
        }
        title_seen = 1
        next
      }
      /^## / {
        if (!title_seen) {
          print "section appears before profile title"
          exit
        }
        if (section != "" && count > 5) {
          print "section has more than 5 bullets: " section
          exit
        }
        section=$0
        sub(/^## /, "", section)
        if (section !~ "^(" allowed ")$") {
          print "section is not allowed: " section
          exit
        }
        count=0
        next
      }
      /^- / {
        if (section == "") {
          print "bullet appears outside an allowed section"
          exit
        }
        count += 1
        next
      }
      {
        print "content appears outside an allowed bullet section"
        exit
      }
      END {
        if (!title_seen) {
          print "profile title is required"
        } else if (section != "" && count > 5) {
          print "section has more than 5 bullets: " section
        }
      }' | head -1)"
  [ -z "$invalid" ] || deny "$invalid"
}

validate_safety() {
  local source_block_pattern='^[[:space:]]*```[[:space:]]*(transcript|chat[-_ ]?log|conversation[-_ ]?log|source[-_ ]?document)'
  local secret_pattern='^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?(export[[:space:]]+)?(api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|bearer[_-]?token)[[:space:]]*[:=][[:space:]]*[^[:space:]]+'

  if grep -Eiq "$source_block_pattern" "$PROFILE_PATH"; then
    deny "profile contains a transcript or source-document block"
  fi
  if grep -Eiq "$secret_pattern" "$PROFILE_PATH"; then
    deny "profile contains a secrets-looking assignment"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift; [ "$#" -gt 0 ] || die "--root requires a value"; ROOT="$1" ;;
    --profile)
      shift; [ "$#" -gt 0 ] || die "--profile requires a value"; PROFILE_PATH="$1" ;;
    --enforce-if-frontmatter)
      ENFORCE_IF_FRONTMATTER=1 ;;
    --require-structured)
      REQUIRE_STRUCTURED=1 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
  shift
done

[ "$COMMAND" = "lint" ] || die "first argument must be lint"
[ -n "$PROFILE_PATH" ] || die "--profile is required"
ROOT="$(cd "$ROOT" && pwd -P)"
[ ! -L "$PROFILE_PATH" ] || die "profile must not be a symlink"
[ -f "$PROFILE_PATH" ] || die "profile is not a file: $PROFILE_PATH"
PROFILE_PATH="$(absolute_path "$PROFILE_PATH")"
validate_safety

char_count="$(wc -m < "$PROFILE_PATH" | tr -d '[:space:]')"
[ "$char_count" -le 1600 ] || deny "profile exceeds 1600 characters"
compact=false
[ "$char_count" -lt 1200 ] || compact=true

schema="legacy"
if profile_has_frontmatter; then
  end_line="$(frontmatter_end_line)"
  [ -n "$end_line" ] || deny "frontmatter is not closed"
  validate_frontmatter "$end_line"
  validate_sections "$((end_line + 1))"
  schema="ok"
elif [ "$REQUIRE_STRUCTURED" -eq 1 ]; then
  deny "structured profile frontmatter is required"
elif [ "$ENFORCE_IF_FRONTMATTER" -eq 0 ]; then
  schema="legacy"
fi

printf 'schema=%s\n' "$schema"
printf 'chars=%s\n' "$char_count"
printf 'compact_recommended=%s\n' "$compact"
