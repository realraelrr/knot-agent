# shellcheck shell=bash

COMPONENT_LOCK_REQUIRED_PATHS="components/docling-skill components/md-for-human components/handoff-skill components/obsidian-wiki components/cc-connect-local-main components/planning-with-files components/knot-skills"
COMPONENT_LOCK_HEADER=$'name\trepo\tref\tpath'
COMPONENT_LOCK_ROWS=0
COMPONENT_LOCK_ERROR=""

component_lock_parse_line() {
  local line="$1"
  local tab=$'\t'
  local rest

  case "$line" in
    *"$tab"*) ;;
    *)
      COMPONENT_LOCK_ERROR="invalid component lock row: expected tab-separated fields"
      return 1
      ;;
  esac

  LOCK_NAME="${line%%"$tab"*}"
  rest="${line#*"$tab"}"
  case "$rest" in
    *"$tab"*) ;;
    *)
      COMPONENT_LOCK_ERROR="invalid component lock row for $LOCK_NAME: missing repo/ref/path"
      return 1
      ;;
  esac

  LOCK_REPO="${rest%%"$tab"*}"
  rest="${rest#*"$tab"}"
  case "$rest" in
    *"$tab"*) ;;
    *)
      COMPONENT_LOCK_ERROR="invalid component lock row for $LOCK_NAME: missing ref/path"
      return 1
      ;;
  esac

  LOCK_REF="${rest%%"$tab"*}"
  LOCK_PATH="${rest#*"$tab"}"
  case "$LOCK_PATH" in
    *"$tab"*)
      COMPONENT_LOCK_ERROR="invalid component lock row for $LOCK_NAME: too many fields"
      return 1
      ;;
  esac
}

component_lock_validate_fields() {
  local component_dir

  [ -n "$LOCK_NAME" ] || {
    COMPONENT_LOCK_ERROR="invalid component lock row: missing name"
    return 1
  }
  [ -n "$LOCK_REPO" ] || {
    COMPONENT_LOCK_ERROR="invalid component lock row for $LOCK_NAME: missing repo"
    return 1
  }
  [ -n "$LOCK_REF" ] || {
    COMPONENT_LOCK_ERROR="invalid component lock row for $LOCK_NAME: missing ref"
    return 1
  }
  [ -n "$LOCK_PATH" ] || {
    COMPONENT_LOCK_ERROR="invalid component lock row for $LOCK_NAME: missing path"
    return 1
  }

  case "$LOCK_NAME" in
    *[!A-Za-z0-9._-]*|""|.*|*..*)
      COMPONENT_LOCK_ERROR="component lock name must be a safe identifier: $LOCK_NAME"
      return 1
      ;;
  esac

  case "$LOCK_REPO" in
    https://github.com/*) ;;
    *)
      COMPONENT_LOCK_ERROR="component lock repo must be a GitHub HTTPS URL: $LOCK_NAME"
      return 1
      ;;
  esac

  case "$LOCK_REF" in
    *[!0-9a-f]*|"")
      COMPONENT_LOCK_ERROR="component lock ref must be a lowercase full SHA: $LOCK_NAME"
      return 1
      ;;
  esac
  if [ "${#LOCK_REF}" -ne 40 ]; then
    COMPONENT_LOCK_ERROR="component lock ref must be a full 40-character SHA: $LOCK_NAME"
    return 1
  fi

  case "$LOCK_PATH" in
    components/*) ;;
    *)
      COMPONENT_LOCK_ERROR="component lock path must stay under components/: $LOCK_NAME"
      return 1
      ;;
  esac

  component_dir="${LOCK_PATH#components/}"
  case "$component_dir" in
    ""|*/*|.*|*..*|*[!A-Za-z0-9._-]*)
      COMPONENT_LOCK_ERROR="component lock path must be components/<safe-dir>: $LOCK_NAME"
      return 1
      ;;
  esac
}

component_lock_validate() {
  local lock_file="$1"
  local report="$2"
  local line
  local invalid=0
  local header_seen=0
  local seen_names=" "
  local seen_paths=" "
  local required_path

  COMPONENT_LOCK_ROWS=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
    esac

    if [ "$line" = "$COMPONENT_LOCK_HEADER" ]; then
      if [ "$header_seen" -eq 1 ]; then
        "$report" "component lock contains duplicate header"
        invalid=1
      fi
      header_seen=1
      continue
    fi

    if ! component_lock_parse_line "$line" || ! component_lock_validate_fields; then
      "$report" "$COMPONENT_LOCK_ERROR"
      invalid=1
      continue
    fi
    COMPONENT_LOCK_ROWS=$((COMPONENT_LOCK_ROWS + 1))

    case "$seen_names" in
      *" $LOCK_NAME "*)
        "$report" "component lock contains duplicate name: $LOCK_NAME"
        invalid=1
        ;;
      *) seen_names="${seen_names}${LOCK_NAME} " ;;
    esac

    case "$seen_paths" in
      *" $LOCK_PATH "*)
        "$report" "component lock contains duplicate path: $LOCK_PATH"
        invalid=1
        ;;
      *) seen_paths="${seen_paths}${LOCK_PATH} " ;;
    esac
  done < "$lock_file"

  if [ "$header_seen" -eq 0 ]; then
    "$report" "component lock header missing"
    invalid=1
  fi
  if [ "$COMPONENT_LOCK_ROWS" -eq 0 ]; then
    "$report" "component lock has no component rows"
    invalid=1
  fi
  for required_path in $COMPONENT_LOCK_REQUIRED_PATHS; do
    case "$seen_paths" in
      *" $required_path "*) ;;
      *)
        "$report" "component lock missing required path: $required_path"
        invalid=1
        ;;
    esac
  done

  [ "$invalid" -eq 0 ]
}

component_lock_each_row() {
  local lock_file="$1"
  local callback="$2"
  local line

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
    esac
    [ "$line" = "$COMPONENT_LOCK_HEADER" ] && continue
    component_lock_parse_line "$line" || return 1
    "$callback" "$LOCK_NAME" "$LOCK_REPO" "$LOCK_REF" "$LOCK_PATH" || return 1
  done < "$lock_file"
}
