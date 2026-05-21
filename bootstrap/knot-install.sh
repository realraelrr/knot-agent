#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib.sh"
BACKUP_REMOTE_URL=""
SKIP_BACKUP_REMOTE=0
SKIP_COMPONENTS=0
SKIP_BUILD=0
SKIP_DOCTOR=0
# Update these pins with the component pin workflow in .skills/knot-setup/SKILL.md.
DOCLING_SKILL_REF="02a9659fdb09312f8abe844b97a97ad9a782bb9d"
MD_FOR_HUMAN_REF="d329bc8b8a22c081d19e0b849418faef013881b3"
HANDOFF_SKILL_REF="744fa700203fcdcab31127fccfb6b5c15b07abbe"
OBSIDIAN_WIKI_REF="6f20faaa0f3b53fa8917816baf5ccbb36f93da72"
CC_CONNECT_REF="2a05067ac621358cfbb8d3b712d6a0eb3cb35758"
PLANNING_WITH_FILES_REF="0587a48d102ae53821668188a12555b167483aaa"
KNOT_SKILLS_REF="d8094f2f9277045b0f3a857a8c9a26dcf38cd810"

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-install.sh [options]

Options:
  --root DIR             Knot root. Defaults to the parent of this script.
  --backup-remote URL    Customer-controlled git remote URL/path named backup.
  --skip-backup-remote   Do not configure or require the backup remote.
  --skip-components      Do not clone component repositories.
  --skip-build           Do not build cc-connect.
  --skip-doctor          Do not run bootstrap/doctor.sh at the end.
  --help, -h             Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || die "--root requires a value"
      ROOT="$1"
      ;;
    --backup-remote)
      shift
      [ "$#" -gt 0 ] || die "--backup-remote requires a value"
      BACKUP_REMOTE_URL="$1"
      ;;
    --skip-backup-remote)
      SKIP_BACKUP_REMOTE=1
      ;;
    --skip-components)
      SKIP_COMPONENTS=1
      ;;
    --skip-build)
      SKIP_BUILD=1
      ;;
    --skip-doctor)
      SKIP_DOCTOR=1
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

mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd)"
cd "$ROOT"

require_file() {
  local path="$1"
  [ -f "$path" ] || die "required file missing: $path"
}

fetch_component_ref() {
  local dir="$1"
  local url="$2"
  local ref="$3"

  git -C "$dir" fetch --depth 1 --no-tags "$url" "$ref"
  git -C "$dir" checkout -q --detach FETCH_HEAD
}

clone_component() {
  local url="$1"
  local dir="$2"
  local ref="$3"
  local current
  local tmp_dir

  if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
    tmp_dir="$dir.tmp.$$"
    rm -rf "$tmp_dir"
    git init -q "$tmp_dir"
    if fetch_component_ref "$tmp_dir" "$url" "$ref"; then
      mv "$tmp_dir" "$dir"
    else
      rm -rf "$tmp_dir"
      die "failed to fetch component revision: $url $ref"
    fi
    return
  fi

  [ -d "$dir/.git" ] || die "component exists but is not a git repository: $dir"

  current="$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null || true)"
  if [ "$current" = "$ref" ]; then
    return 0
  fi

  if ! git -C "$dir" diff --quiet --ignore-submodules -- ||
    ! git -C "$dir" diff --cached --quiet --ignore-submodules --; then
    die "component has tracked local changes; refusing to checkout pinned revision: $dir"
  fi

  fetch_component_ref "$dir" "$url" "$ref"
}

link_skill() {
  local name="$1"
  local target="$2"
  local dest="$SKILLS_DIR/$name"
  local backup

  [ -f "$target/SKILL.md" ] || return 0
  target="$(cd "$target" && pwd)"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ]; then
      rm "$dest"
    else
      backup="$dest.backup.$(date +%Y%m%d%H%M%S)"
      mv "$dest" "$backup"
      printf 'Backed up existing skill directory: %s -> %s\n' "$dest" "$backup"
    fi
  fi

  ln -s "$target" "$dest"
}

mkdir -p components runtime \
  workspace/knowledge/raw \
  workspace/knowledge/processed \
  workspace/knowledge/vault \
  workspace/users \
  workspace/groups \
  workspace/conversations \
  workspace/admin \
  workspace/.state/tasks

require_file ".skills/knot-setup/references/permissions.template.md"
require_file ".skills/knot-setup/references/knowledge-feedback.template.md"
require_file ".skills/knot-setup/references/backup-policy.template.md"
require_file ".skills/knot-setup/references/AGENTS.template.md"
require_file ".skills/knot-setup/references/codex-agents.template.md"

test -f workspace/admin/permissions.md || cp .skills/knot-setup/references/permissions.template.md workspace/admin/permissions.md
test -f workspace/admin/knowledge-feedback.md || cp .skills/knot-setup/references/knowledge-feedback.template.md workspace/admin/knowledge-feedback.md
test -f workspace/admin/backup-policy.md || cp .skills/knot-setup/references/backup-policy.template.md workspace/admin/backup-policy.md
test -f AGENTS.md || cp .skills/knot-setup/references/AGENTS.template.md AGENTS.md

for helper in bootstrap/*.sh; do
  [ -f "$helper" ] || continue
  [ "$(basename "$helper")" != "lib.sh" ] || continue
  chmod +x "$helper"
done

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
GLOBAL_AGENTS="$CODEX_HOME_DIR/AGENTS.md"
GLOBAL_AGENTS_TEMPLATE=".skills/knot-setup/references/codex-agents.template.md"
SKILLS_DIR="$CODEX_HOME_DIR/skills"

mkdir -p "$CODEX_HOME_DIR" "$SKILLS_DIR"
if [ -f "$CODEX_HOME_DIR/AGENTS.override.md" ]; then
  printf 'Warning: %s exists and overrides %s until removed.\n' \
    "$CODEX_HOME_DIR/AGENTS.override.md" "$GLOBAL_AGENTS"
fi

if [ ! -e "$GLOBAL_AGENTS" ] && [ ! -L "$GLOBAL_AGENTS" ]; then
  cp "$GLOBAL_AGENTS_TEMPLATE" "$GLOBAL_AGENTS"
  printf 'Installed global Codex instructions: %s\n' "$GLOBAL_AGENTS"
elif [ -f "$GLOBAL_AGENTS" ] && cmp -s "$GLOBAL_AGENTS_TEMPLATE" "$GLOBAL_AGENTS"; then
  printf 'Global Codex instructions already match template: %s\n' "$GLOBAL_AGENTS"
else
  printf 'Global Codex instructions already exist: %s\n' "$GLOBAL_AGENTS"
  printf 'Inspect and merge manually before replacing user custom instructions.\n'
fi

if [ "$SKIP_BACKUP_REMOTE" -eq 0 ]; then
  if [ -n "$BACKUP_REMOTE_URL" ]; then
    if git remote get-url backup >/dev/null 2>&1; then
      git remote set-url backup "$BACKUP_REMOTE_URL"
    else
      git remote add backup "$BACKUP_REMOTE_URL"
    fi
  elif ! git remote get-url backup >/dev/null 2>&1; then
    printf 'Warning: backup remote is not configured; daily rollback backup is not ready.\n'
  fi
fi

if [ "$SKIP_COMPONENTS" -eq 0 ]; then
  clone_component https://github.com/realraelrr/docling-skill components/docling-skill "$DOCLING_SKILL_REF"
  clone_component https://github.com/realraelrr/md-for-human components/md-for-human "$MD_FOR_HUMAN_REF"
  clone_component https://github.com/realraelrr/handoff-skill components/handoff-skill "$HANDOFF_SKILL_REF"
  clone_component https://github.com/Ar9av/obsidian-wiki components/obsidian-wiki "$OBSIDIAN_WIKI_REF"
  clone_component https://github.com/realraelrr/cc-connect components/cc-connect-local-main "$CC_CONNECT_REF"
  clone_component https://github.com/realraelrr/planning-with-files components/planning-with-files "$PLANNING_WITH_FILES_REF"
  clone_component https://github.com/realraelrr/knot-skills components/knot-skills "$KNOT_SKILLS_REF"
fi

if [ -x components/knot-skills/scripts/install-codex-skills.sh ]; then
  KNOT_ROOT="$ROOT" bash components/knot-skills/scripts/install-codex-skills.sh
fi

if [ -d components/obsidian-wiki/.skills ]; then
  find components/obsidian-wiki/.skills -mindepth 1 -maxdepth 1 -type d -exec sh -c '
    set -e
    skills_dir="$1"
    shift
    for d do
      name="$(basename "$d")"
      dest="$skills_dir/$name"
      target="$(cd "$d" && pwd)"
      if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ -L "$dest" ]; then
          rm "$dest"
        else
          backup="$dest.backup.$(date +%Y%m%d%H%M%S)"
          mv "$dest" "$backup"
          printf "Backed up existing skill directory: %s -> %s\n" "$dest" "$backup"
        fi
      fi
      ln -s "$target" "$dest"
    done
  ' sh "$SKILLS_DIR" {} +
fi

link_skill planning-with-files components/planning-with-files/.codex/skills/planning-with-files
link_skill docling-skill components/docling-skill/.codex/skills/docling-skill
link_skill md-for-human components/md-for-human/.codex/skills/md-for-human
link_skill handoff components/handoff-skill/.codex/skills/handoff
link_skill knot-setup .skills/knot-setup
link_skill knot-workflow .skills/knot-workflow

if [ "$SKIP_BUILD" -eq 0 ]; then
  if [ -d components/cc-connect-local-main ]; then
    make -C components/cc-connect-local-main build-noweb
    if [ -x components/cc-connect-local-main/cc-connect ]; then
      components/cc-connect-local-main/cc-connect --version
    elif [ -x components/cc-connect-local-main/dist/cc-connect ]; then
      components/cc-connect-local-main/dist/cc-connect --version
    else
      printf 'ERROR cc-connect binary not found after build\n' >&2
      exit 1
    fi
  else
    printf 'Warning: cc-connect source missing; skipped build.\n'
  fi
fi

if [ "$SKIP_DOCTOR" -eq 0 ]; then
  bash bootstrap/doctor.sh
fi
