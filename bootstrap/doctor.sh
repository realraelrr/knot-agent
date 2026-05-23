#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=bootstrap/lib.sh
. "$SCRIPT_DIR/lib.sh"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DIR="$CODEX_HOME_DIR/skills"
WORKSPACE="$ROOT/workspace"
PLATFORMS=""
SCAFFOLD_ONLY=0
STRICT_DOCS=0
FAILURES=0
WARNINGS=0
COMPONENT_LOCK="$ROOT/components.lock"
REQUIRED_COMPONENT_PATHS="components/docling-skill components/md-for-human components/handoff-skill components/obsidian-wiki components/cc-connect-local-main components/planning-with-files components/knot-skills"
KNOWLEDGE_FEEDBACK_HEADER="| Time | Platform | Chat ID | Platform User ID | Identity Key | Name | Topic | Feedback | Evidence | Diff | Status | Execution | Admin Notes |"

# shellcheck source=bootstrap/doctor/common.sh
. "$SCRIPT_DIR/doctor/common.sh" || exit 1

usage() {
  cat <<'EOF'
Usage: bash bootstrap/doctor.sh [--scaffold-only] [--strict-docs] [--platform NAME[,NAME...]]

Platform names: dingtalk, feishu, wecom, weixin
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
      PLATFORMS="${PLATFORMS}${PLATFORMS:+,}$1"
      ;;
    --scaffold-only)
      SCAFFOLD_ONLY=1
      ;;
    --strict-docs)
      STRICT_DOCS=1
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

# shellcheck source=bootstrap/doctor/source.sh
. "$SCRIPT_DIR/doctor/source.sh" || {
  fail "doctor source checks module unavailable"
  exit 1
}
# shellcheck source=bootstrap/doctor/installed.sh
. "$SCRIPT_DIR/doctor/installed.sh" || {
  fail "doctor installed checks module unavailable"
  exit 1
}

printf 'Knot doctor\n'
printf 'Root: %s\n\n' "$ROOT"

if [ "$SCAFFOLD_ONLY" -eq 1 ]; then
  run_scaffold_only_checks
  printf '\nDone.\n'
  if [ "$WARNINGS" -gt 0 ]; then
    printf 'WARNED %s advisory check(s).\n' "$WARNINGS"
  fi
  if [ "$FAILURES" -gt 0 ]; then
    printf 'FAILED %s required check(s).\n' "$FAILURES"
    exit 1
  fi
  exit 0
fi

run_local_environment_checks
run_source_structure_checks
run_skill_link_checks
run_component_checks
run_workspace_structure_checks
run_contract_checks
run_workspace_contract_checks
run_doc_lint_checks
check_backup_remote
run_smoke_checks
run_runtime_checks

printf '\nDone.\n'

if [ "$WARNINGS" -gt 0 ]; then
  printf 'WARNED %s advisory check(s).\n' "$WARNINGS"
fi

if [ "$FAILURES" -gt 0 ]; then
  printf 'FAILED %s required check(s).\n' "$FAILURES"
  exit 1
fi
