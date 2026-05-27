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
WRITE_SIDECAR=0
ENFORCE_IF_FRONTMATTER=0
REQUIRE_STRUCTURED=0
SCOPE=""
USER_SLUG=""
USER_WORKSPACE=""
ALLOWED_SECTIONS="Communication|Evidence And Review|Delivery|Recurring Workflows|Avoid"

usage() {
  cat <<'EOF'
Usage: bash bin/knot-collaborator-profile-lint.sh lint --profile FILE [options]

Options:
  --root DIR
  --profile FILE
  --write-sidecar
  --enforce-if-frontmatter
  --require-structured
  --scope direct
  --actor-user SLUG
  --user-workspace DIR
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

detect_conflicts() {
  local body
  body="$(tr '[:upper:]' '[:lower:]' < "$PROFILE_PATH")"
  conflicts=0
  if printf '%s\n' "$body" | grep -q 'concise' &&
    printf '%s\n' "$body" | grep -q 'detailed'; then
    conflicts=$((conflicts + 1))
  fi
  if printf '%s\n' "$body" | grep -q 'chinese' &&
    printf '%s\n' "$body" | grep -q 'english'; then
    conflicts=$((conflicts + 1))
  fi
  printf '%s\n' "$conflicts"
}

sidecar_path() {
  printf '%s\n' "$USER_WORKSPACE/.knot/collaborator-profile-conflicts.json"
}

write_conflict_sidecar() {
  local count="$1"
  local path
  local expected_workspace

  [ "$SCOPE" = "direct" ] || deny "conflict sidecar writes require direct scope"
  [ -n "$USER_SLUG" ] || deny "--actor-user is required for conflict sidecar writes"
  validate_slug "--actor-user" "$USER_SLUG"
  [ -n "$USER_WORKSPACE" ] || deny "--user-workspace is required for conflict sidecar writes"
  expected_workspace="$(absolute_path "$ROOT/workspace/users/$USER_SLUG")" ||
    deny "cannot resolve expected user workspace"
  USER_WORKSPACE="$(absolute_path "$USER_WORKSPACE")" || deny "cannot resolve user workspace"
  [ "$USER_WORKSPACE" = "$expected_workspace" ] ||
    deny "conflict sidecar user workspace does not match actor"
  path_is_under "$PROFILE_PATH" "$USER_WORKSPACE/collaboration" ||
    deny "conflict sidecar profile must be under the actor collaboration directory"
  ensure_dir_no_symlink "$USER_WORKSPACE/.knot" "collaborator profile runtime context"
  path="$(sidecar_path)"
  [ ! -L "$path" ] || deny "conflict sidecar must not be a symlink"
  if [ "$count" -eq 0 ]; then
    rm -f "$path"
    return
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
{
  "profile_sha256": "$(file_sha256 "$PROFILE_PATH")",
  "conflicts": $count,
  "redacted": true,
  "hints": ["communication_preference_conflict"]
}
EOF
  chmod 600 "$path"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift; [ "$#" -gt 0 ] || die "--root requires a value"; ROOT="$1" ;;
    --profile)
      shift; [ "$#" -gt 0 ] || die "--profile requires a value"; PROFILE_PATH="$1" ;;
    --write-sidecar)
      WRITE_SIDECAR=1 ;;
    --enforce-if-frontmatter)
      ENFORCE_IF_FRONTMATTER=1 ;;
    --require-structured)
      REQUIRE_STRUCTURED=1 ;;
    --scope)
      shift; [ "$#" -gt 0 ] || die "--scope requires a value"; SCOPE="$1" ;;
    --actor-user|--user-slug)
      shift; [ "$#" -gt 0 ] || die "--actor-user requires a value"; USER_SLUG="$1" ;;
    --user-workspace)
      shift; [ "$#" -gt 0 ] || die "--user-workspace requires a value"; USER_WORKSPACE="$1" ;;
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

conflicts="$(detect_conflicts)"
if [ "$WRITE_SIDECAR" -eq 1 ]; then
  write_conflict_sidecar "$conflicts"
fi

printf 'schema=%s\n' "$schema"
printf 'chars=%s\n' "$char_count"
printf 'compact_recommended=%s\n' "$compact"
printf 'conflicts=%s\n' "$conflicts"
