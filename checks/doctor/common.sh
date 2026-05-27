# shellcheck shell=bash

ok() { printf 'OK   %s\n' "$1"; }

warn() {
  printf 'WARN %s\n' "$1"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

doc_lint() {
  if [ "$STRICT_DOCS" -eq 1 ]; then
    fail "$1"
  else
    warn "$1"
  fi
}

check_dir() {
  if [ -d "$1" ]; then
    ok "$2: $1"
  else
    fail "$2 missing: $1"
  fi
}

check_file_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [ ! -f "$path" ]; then
    fail "$label missing: $path"
    return
  fi

  if grep -Fq -- "$pattern" "$path"; then
    ok "$label contains: $pattern"
  else
    fail "$label missing required text: $pattern"
  fi
}

check_file_exists() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    ok "$label: $path"
    return 0
  fi

  fail "$label missing: $path"
  return 1
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

check_file_not_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [ ! -f "$path" ]; then
    fail "$label missing: $path"
    return
  fi

  if grep -Fq -- "$pattern" "$path"; then
    fail "$label contains stale text: $pattern"
  else
    ok "$label does not contain stale text: $pattern"
  fi
}

check_file_contains_doc_lint() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [ ! -f "$path" ]; then
    doc_lint "$label missing: $path"
    return
  fi

  if grep -Fq -- "$pattern" "$path"; then
    ok "$label contains: $pattern"
  else
    doc_lint "$label missing advisory text: $pattern"
  fi
}

check_file_not_contains_doc_lint() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if [ ! -f "$path" ]; then
    doc_lint "$label missing: $path"
    return
  fi

  if grep -Fq -- "$pattern" "$path"; then
    doc_lint "$label contains stale text: $pattern"
  else
    ok "$label does not contain stale text: $pattern"
  fi
}

check_operations_docs() {
  check_file_exists "$ROOT/docs/ops/release-gate.md" "release gate"
  check_file_exists "$ROOT/docs/ops/component-sync.md" "component sync SOP"
  check_file_exists "$ROOT/docs/ops/deployment-inputs.md" "deployment inputs"
  check_file_exists "$ROOT/docs/ops/deployment-profiles.md" "deployment profiles"
  check_file_exists "$ROOT/docs/schemas/audit-event-semantics.md" "audit event semantics"
}

check_permissions_table_schema() {
  local path="$1"
  local label="$2"
  local expected_header="| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |"
  local output

  check_file_exists "$path" "$label" || return
  if ! grep -Fxq "$expected_header" "$path"; then
    fail "$label header mismatch"
    return
  fi

  output="$(awk -F'|' '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    function valid_slug(s) {
      return s ~ /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/
    }
    function report(msg) {
      print msg
      bad = 1
    }
    /^\|/ {
      if (NF != 13) {
        report("line " NR " has " NF " pipe fields, expected 13")
        next
      }
      user = trim($2)
      workspace = trim($3)
      platform = trim($4)
      platform_user = trim($5)
      group_slug = trim($6)
      chat_id = trim($7)
      identity_key = trim($8)
      role = trim($10)
      scope = trim($11)

      if (user == "User" || user == "---") {
        next
      }
      if (user == "" && workspace == "" && platform == "" && platform_user == "" &&
          group_slug == "" && chat_id == "" && identity_key == "" && role == "" && scope == "") {
        next
      }

      if (workspace == "" || !valid_slug(workspace)) {
        report("line " NR " has invalid Workspace slug: " workspace)
      }
      if (group_slug != "" && !valid_slug(group_slug)) {
        report("line " NR " has invalid Group slug: " group_slug)
      }
      if (platform != "" && platform !~ /^(dingtalk|feishu|wecom|weixin)$/) {
        report("line " NR " has unknown Platform: " platform)
      }
      if (role != "" && role !~ /^(operator|admin|member)$/) {
        report("line " NR " has unknown Role: " role)
      }
      if (scope != "" && scope !~ /^(all|system|knowledge|session|dept:[A-Za-z0-9._-]+)$/) {
        report("line " NR " has unknown Scope: " scope)
      }

      row_key = user "|" workspace "|" platform "|" platform_user "|" group_slug "|" chat_id "|" identity_key "|" role "|" scope
      if (seen_row[row_key] != "") {
        report("line " NR " duplicates permissions row from line " seen_row[row_key])
      }
      seen_row[row_key] = NR

      actor_key = ""
      if (identity_key != "") {
        actor_key = "identity:" identity_key
      } else if (platform != "" && platform_user != "") {
        actor_key = "platform:" platform ":" platform_user
      }
      if (actor_key != "") {
        if (actor_workspace[actor_key] != "" && actor_workspace[actor_key] != workspace) {
          report("line " NR " maps actor identity to multiple workspaces")
        }
        actor_workspace[actor_key] = workspace
      }

      if (platform != "" && chat_id != "" && actor_key != "" && group_slug != "") {
        group_key = actor_key "|" platform "|" chat_id
        if (actor_group[group_key] != "" && actor_group[group_key] != group_slug) {
          report("line " NR " maps actor chat context to multiple groups")
        }
        actor_group[group_key] = group_slug

        group_context_key = group_key "|" group_slug
        if (actor_group_context[group_context_key] != "") {
          report("line " NR " duplicates actor chat context from line " actor_group_context[group_context_key])
        }
        actor_group_context[group_context_key] = NR
      }

      if (actor_key != "" && platform != "" && chat_id == "" && group_slug == "") {
        direct_context_key = actor_key "|" platform
        if (actor_direct_context[direct_context_key] != "") {
          report("line " NR " duplicates direct actor context from line " actor_direct_context[direct_context_key])
        }
        actor_direct_context[direct_context_key] = NR
      }
    }
    END { exit bad ? 1 : 0 }
  ' "$path" 2>&1)" && {
    ok "$label schema"
    return
  }

  while IFS= read -r line; do
    [ -n "$line" ] && fail "$label schema: $line"
  done <<EOF
$output
EOF
}

run_helper_smoke_tests() {
  if ! bash "$ROOT/tests/integration.sh" --root "$ROOT"; then
    fail "integration smoke tests failed"
  fi
  if ! bash "$ROOT/bin/knot-permission-smoke.sh" --root "$ROOT"; then
    fail "permission smoke tests failed"
  fi
}

run_smoke_checks() {
  printf '\nSmoke tests\n'
  run_helper_smoke_tests
}
