# shellcheck shell=bash
# shellcheck disable=SC2154

FAILURES=0
TMP_PARENT=""
UNSAFE_ROOT=""

# shellcheck source=lib/knot/core.sh
. "$ROOT/lib/knot/core.sh"

ok() { printf 'OK   %s\n' "$1"; }
fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

assert_event_schema() {
  local path="$1"
  local schema="$ROOT/docs/schemas/audit-event.schema.json"
  local required_keys
  local resource_events

  if [ ! -s "$path" ]; then
    fail "event log is empty or missing: $path"
    return
  fi
  if [ ! -s "$schema" ]; then
    fail "audit event schema is missing: $schema"
    return
  fi
  if ! required_keys="$(jq -c '.required' "$schema" 2>/dev/null)" ||
    ! resource_events="$(jq -c '."x-knot-resource-events"' "$schema" 2>/dev/null)"; then
    fail "audit event schema is not valid JSON"
    return
  fi

  if jq -c . "$path" >/dev/null 2>&1 &&
    jq -s -e --argjson keys "$required_keys" \
      'all(.[]; ([keys_unsorted[]] | sort) == ($keys | sort))' "$path" >/dev/null &&
    jq -s -e --argjson resource_events "$resource_events" \
      'all(.[]; .event as $event | if ($resource_events | index($event)) then true else (.resource_kind == "" and .resource_path == "" and .resource_sha256 == "" and .resource_size_bytes == 0) end)' "$path" >/dev/null; then
    ok "event log rows use external compact audit schema"
  else
    fail "event log rows do not match external audit schema"
  fi

  if python3 - "$path" "$schema" <<'PY' >/dev/null 2>&1
import json
import re
import sys

path, schema_path = sys.argv[1], sys.argv[2]
schema = json.load(open(schema_path, encoding="utf-8"))
props = schema["properties"]
required = set(schema["required"])

for line in open(path, encoding="utf-8"):
    event = json.loads(line)
    if set(event) != required:
        raise SystemExit(1)
    for key, rule in props.items():
        value = event[key]
        if "const" in rule and value != rule["const"]:
            raise SystemExit(1)
        if "enum" in rule and value not in rule["enum"]:
            raise SystemExit(1)
        if "pattern" in rule and not re.match(rule["pattern"], value):
            raise SystemExit(1)
        if rule.get("type") == "integer" and not isinstance(value, int):
            raise SystemExit(1)
        if rule.get("type") == "string" and not isinstance(value, str):
            raise SystemExit(1)
PY
  then
    ok "event log rows satisfy compact audit enum and pattern schema"
  else
    fail "event log rows violate compact audit enum or pattern schema"
  fi
}

cleanup() {
  [ -z "$TMP_PARENT" ] || rm -rf "$TMP_PARENT"
  [ -z "$UNSAFE_ROOT" ] || rm -rf "$UNSAFE_ROOT"
}
trap cleanup EXIT
