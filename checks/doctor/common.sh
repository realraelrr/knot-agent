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
