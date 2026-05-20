#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib.sh"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DIR="$CODEX_HOME_DIR/skills"
PLATFORMS=""
FAILURES=0

ok() { printf 'OK   %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; }
fail() {
  printf 'MISS %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

usage() {
  cat <<'EOF'
Usage: bash bootstrap/doctor.sh [--platform NAME[,NAME...]]

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

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1: $(command -v "$1")"
  else
    fail "$1 command not found"
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

check_backup_remote() {
  if [ ! -d "$ROOT/.git" ]; then
    fail "backup git repository missing: $ROOT/.git"
    return
  fi

  local backup_url
  backup_url="$(git -C "$ROOT" remote get-url backup 2>/dev/null)" || {
    fail "backup remote missing; configure customer-controlled remote named backup"
    return
  }

  if printf '%s\n' "$backup_url" | grep -qi 'realraelrr/knot-agent'; then
    fail "backup remote points to scaffold repository: $backup_url"
  else
    ok "backup remote: $backup_url"
  fi

  local unsafe_remote
  local unsafe_url
  for unsafe_remote in origin scaffold; do
    unsafe_url="$(git -C "$ROOT" remote get-url "$unsafe_remote" 2>/dev/null || true)"
    if [ -n "$unsafe_url" ] && [ "$backup_url" = "$unsafe_url" ]; then
      fail "backup remote matches $unsafe_remote; configure a customer-controlled backup remote"
    fi
  done
}

run_helper_smoke_tests() {
  local tmp_root
  local tmp_parent
  local workspace_exports
  local user_workspace
  local group_workspace
  local conversation_dir

  tmp_parent="$(mktemp -d)"
  tmp_root="$tmp_parent/root with spaces"
  mkdir -p "$tmp_root"

  workspace_exports="$(bash "$ROOT/bootstrap/knot-workspace.sh" \
    --root "$tmp_root" \
    --platform feishu \
    --chat-id "oc/test group" \
    --user-id "ou/test user" \
    --user-slug "example-user" \
    --group-slug "example-group" \
    --identity-key "feishu:user:ou-test" \
    --name "Smoke Test" \
    --group-name "Example Group")" || {
    fail "knot-workspace smoke test failed"
    rm -rf "$tmp_parent"
    return
  }

  if eval "$workspace_exports" &&
    [ "$KNOT_ACTIVE_WORKSPACE" = "$tmp_root/workspace/users/example-user" ] &&
    [ "$KNOT_USER_WORKSPACE" = "$tmp_root/workspace/users/example-user" ] &&
    [ "$KNOT_GROUP_WORKSPACE" = "$tmp_root/workspace/groups/example-group" ] &&
    [ -n "$KNOT_CONVERSATION_DIR" ]; then
    ok "knot-workspace prints source-safe exports for paths with spaces"
  else
    fail "knot-workspace exports did not resolve expected user/group paths"
  fi

  user_workspace="$tmp_root/workspace/users/example-user"
  group_workspace="$tmp_root/workspace/groups/example-group"
  conversation_dir="$KNOT_CONVERSATION_DIR"

  if [ -d "$user_workspace/deliverables" ] &&
    [ -d "$group_workspace/deliverables" ] &&
    [ -f "$conversation_dir/metadata.tsv" ] &&
    grep -Fq $'actor_user\texample-user' "$conversation_dir/metadata.tsv" &&
    [ ! -d "$tmp_root/workspace/sessions" ]; then
    ok "knot-workspace creates user/group workspaces and conversation metadata only"
  else
    fail "knot-workspace did not create expected user/group/conversation state"
  fi

  mkdir -p "$tmp_root/workspace/admin"
  cat > "$tmp_root/workspace/admin/permissions.md" <<'EOF'
| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Example User | example-user | feishu | ou/test user | example-group | oc/test group | feishu:user:ou-test | Smoke Test | member | session | smoke |
| Jane Example | jane-example | feishu | ou/jane | product-room | oc/product | feishu:user:ou/jane | Jane Example | member | session | smoke |
EOF
  local resolved_exports
  if resolved_exports="$(bash "$ROOT/bootstrap/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/jane" --identity-key "feishu:user:ou/jane" --name "Ignored Name" --group-name "Ignored Group")" &&
    eval "$resolved_exports" &&
    [ "$KNOT_ACTIVE_WORKSPACE" = "$tmp_root/workspace/users/jane-example" ] &&
    [ "$KNOT_GROUP_WORKSPACE" = "$tmp_root/workspace/groups/product-room" ]; then
    ok "knot-workspace resolves user/group slugs from permissions table"
  else
    fail "knot-workspace did not resolve permissions table slugs"
  fi

  if resolved_exports="$(bash "$ROOT/bootstrap/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id "oc/product" --user-id "ou/bob" --identity-key "feishu:user:ou/bob" --name "Bob Example" --group-name "Ignored Group")" &&
    eval "$resolved_exports" &&
    [ -z "$KNOT_GROUP_WORKSPACE" ]; then
    ok "knot-workspace requires actor match before exposing permissions group"
  else
    fail "knot-workspace exposed permissions group to unmatched actor"
  fi

  if bash "$ROOT/bootstrap/knot-workspace.sh" --root "$tmp_root" --platform feishu --chat-id $'oc/bad\tchat' --user-id "ou/test user" --user-slug "bad-meta" >/dev/null 2>&1; then
    fail "knot-workspace allowed tab in chat metadata"
  else
    ok "knot-workspace rejects tabs in chat metadata"
  fi

  printf 'ok\n' > "$user_workspace/deliverables/result.txt"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/result.txt" >/dev/null; then
    ok "knot-attachment allows current user deliverable"
  else
    fail "knot-attachment rejected current user deliverable"
  fi

  printf 'group\n' > "$group_workspace/deliverables/group.txt"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$group_workspace/deliverables/group.txt" >/dev/null; then
    ok "knot-attachment allows current group deliverable"
  else
    fail "knot-attachment rejected current group deliverable"
  fi

  mkdir -p "$tmp_root/generated"
  printf 'generated\n' > "$tmp_root/generated/image.png"
  local deliver_output
  if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$tmp_root/generated/image.png")"; then
    local expected_deliverable
    expected_deliverable="$(resolve_path "$user_workspace/deliverables/image.png")"
    if [ -f "$user_workspace/deliverables/image.png" ] &&
      printf '%s\n' "$deliver_output" | grep -Fq '```cc-connect-attachments' &&
      printf '%s\n' "$deliver_output" | grep -Fq "image: $expected_deliverable"; then
      ok "knot-deliver copies generated artifact to user deliverables"
    else
      fail "knot-deliver did not copy generated artifact to user deliverables"
    fi
  else
    fail "knot-deliver rejected generated artifact"
  fi

  if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$tmp_root/generated/image.png" --target group --output-name "shared.png")"; then
    if [ -f "$group_workspace/deliverables/shared.png" ] &&
      printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/shared.png")"; then
      ok "knot-deliver can target current group deliverables explicitly"
    else
      fail "knot-deliver did not copy generated artifact to group deliverables"
    fi
  else
    fail "knot-deliver rejected explicit group delivery"
  fi

  printf 'env-generated\n' > "$tmp_root/generated/env.png"
  if deliver_output="$(env \
    KNOT_ROOT="$tmp_root" \
    KNOT_PLATFORM=feishu \
    KNOT_PLATFORM_USER_ID="ou/test user" \
    KNOT_ACTOR_USER=example-user \
    KNOT_SOURCE_GROUP=example-group \
    KNOT_CHAT_ID="oc/test group" \
    KNOT_IDENTITY_KEY="feishu:user:ou-test" \
    bash "$ROOT/bootstrap/knot-deliver.sh" --kind image --path "$tmp_root/generated/env.png" --target group --output-name "env-shared.png")"; then
    if [ -f "$group_workspace/deliverables/env-shared.png" ] &&
      printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/env-shared.png")"; then
      ok "knot-deliver reads current context from KNOT_* environment"
    else
      fail "knot-deliver env-context delivery did not create expected group deliverable"
    fi
  else
    fail "knot-deliver did not accept KNOT_* environment context"
  fi

  if attach_output="$(env \
    KNOT_ROOT="$tmp_root" \
    KNOT_PLATFORM=feishu \
    KNOT_PLATFORM_USER_ID="ou/test user" \
    KNOT_ACTOR_USER=example-user \
    KNOT_SOURCE_GROUP=example-group \
    KNOT_CHAT_ID="oc/test group" \
    KNOT_IDENTITY_KEY="feishu:user:ou-test" \
    bash "$ROOT/bootstrap/knot-attachment.sh" --kind image --path "$group_workspace/deliverables/env-shared.png")" &&
    printf '%s\n' "$attach_output" | grep -Fq "image: $(resolve_path "$group_workspace/deliverables/env-shared.png")"; then
    ok "knot-attachment reads current context from KNOT_* environment"
  else
    fail "knot-attachment did not accept KNOT_* environment context"
  fi

  local unauthorized_output
  if unauthorized_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "unauthorized-group" --kind image --path "$tmp_root/generated/image.png" --target group 2>&1)"; then
    fail "knot-deliver allowed unauthorized explicit group delivery"
  elif printf '%s\n' "$unauthorized_output" | grep -Fq "not authorized"; then
    ok "knot-deliver rejects unauthorized explicit group delivery"
  else
    fail "knot-deliver unauthorized group rejection had wrong error: $unauthorized_output"
  fi

  if unauthorized_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --identity-key "feishu:user:wrong" --kind image --path "$tmp_root/generated/image.png" --target group 2>&1)"; then
    fail "knot-deliver allowed group delivery with mismatched identity key"
  elif printf '%s\n' "$unauthorized_output" | grep -Fq "not authorized"; then
    ok "knot-deliver rejects mismatched identity key for group delivery"
  else
    fail "knot-deliver identity mismatch rejection had wrong error: $unauthorized_output"
  fi

  if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/result.txt" --target group --output-name "result-shared.txt")"; then
    if [ -f "$group_workspace/deliverables/result-shared.txt" ] &&
      printf '%s\n' "$deliver_output" | grep -Fq "file: $(resolve_path "$group_workspace/deliverables/result-shared.txt")"; then
      ok "knot-deliver copies user deliverable into group deliverables when target is group"
    else
      fail "knot-deliver did not copy user deliverable into group deliverables"
    fi
  else
    fail "knot-deliver rejected user deliverable targeted to group"
  fi

  ln -s "$tmp_root/escaped-delivery.png" "$user_workspace/deliverables/symlink.png"
  if deliver_output="$(bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind image --path "$tmp_root/generated/image.png" --output-name "symlink.png")"; then
    if [ ! -e "$tmp_root/escaped-delivery.png" ] &&
      [ -f "$user_workspace/deliverables/symlink-1.png" ] &&
      printf '%s\n' "$deliver_output" | grep -Fq "image: $(resolve_path "$user_workspace/deliverables/symlink-1.png")"; then
      ok "knot-deliver avoids writing through deliverables symlinks"
    else
      fail "knot-deliver wrote through or failed to avoid deliverables symlink"
    fi
  else
    fail "knot-deliver rejected delivery when output name collided with symlink"
  fi

  local other_user_workspace
  other_user_workspace="$tmp_root/workspace/users/other-user"
  mkdir -p "$other_user_workspace/deliverables"
  printf 'private\n' > "$other_user_workspace/deliverables/private.txt"
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_user_workspace/deliverables/private.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed artifact from another user workspace"
  else
    ok "knot-deliver rejects artifact from another user workspace"
  fi

  local other_group_workspace
  other_group_workspace="$tmp_root/workspace/groups/other-group"
  mkdir -p "$other_group_workspace/deliverables"
  printf 'group-private\n' > "$other_group_workspace/deliverables/private.txt"
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_group_workspace/deliverables/private.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed artifact from another group workspace"
  else
    ok "knot-deliver rejects artifact from another group workspace"
  fi

  printf 'audit\n' > "$conversation_dir/audit.txt"
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$conversation_dir/audit.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed artifact from conversations metadata"
  else
    ok "knot-deliver rejects artifact from conversations metadata"
  fi

  printf 'external\n' > "$tmp_root/generated/external.txt"
  ln -s "$tmp_root/generated/external.txt" "$other_user_workspace/deliverables/external-link.txt"
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$other_user_workspace/deliverables/external-link.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed symlink path from another user workspace"
  else
    ok "knot-deliver rejects symlink path from another user workspace"
  fi

  printf 'outside\n' > "$tmp_root/outside.txt"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$tmp_root/outside.txt" >/dev/null 2>&1; then
    fail "knot-attachment allowed file outside current user/group workspaces"
  else
    ok "knot-attachment rejects file outside current user/group workspaces"
  fi

  ln -s "$tmp_root/outside.txt" "$user_workspace/deliverables/leak.txt"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables/leak.txt" >/dev/null 2>&1; then
    fail "knot-attachment allowed symlink escaping current user workspace"
  else
    ok "knot-attachment rejects symlink escaping current user workspace"
  fi

  mv "$user_workspace/deliverables" "$user_workspace/deliverables-real"
  ln -s "$user_workspace/deliverables-real" "$user_workspace/deliverables"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "example-group" --kind file --path "$user_workspace/deliverables-real/result.txt" >/dev/null 2>&1; then
    fail "knot-attachment allowed symlinked user deliverables directory"
  else
    ok "knot-attachment rejects symlinked user deliverables directory"
  fi
  rm "$user_workspace/deliverables"
  mv "$user_workspace/deliverables-real" "$user_workspace/deliverables"

  ln -s "$user_workspace" "$tmp_root/workspace/users/alias-user"
  if bash "$ROOT/bootstrap/knot-attachment.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "alias-user" --kind file --path "$user_workspace/deliverables/result.txt" >/dev/null 2>&1; then
    fail "knot-attachment allowed symlinked user workspace slug"
  else
    ok "knot-attachment rejects symlinked user workspace slug"
  fi
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "alias-user" --kind file --path "$tmp_root/generated/external.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed symlinked user workspace slug"
  else
    ok "knot-deliver rejects symlinked user workspace slug"
  fi

  ln -s "$group_workspace" "$tmp_root/workspace/groups/alias-group"
  if bash "$ROOT/bootstrap/knot-deliver.sh" --root "$tmp_root" --platform feishu --chat-id "oc/test group" --user-id "ou/test user" --user-slug "example-user" --group-slug "alias-group" --target group --kind file --path "$tmp_root/generated/external.txt" >/dev/null 2>&1; then
    fail "knot-deliver allowed symlinked group workspace slug"
  else
    ok "knot-deliver rejects symlinked group workspace slug"
  fi

  local unsafe_root
  unsafe_root="$(mktemp -d)"
  git -C "$unsafe_root" init >/dev/null 2>&1
  git -C "$unsafe_root" remote add backup https://github.com/realraelrr/knot-agent.git
  if bash "$ROOT/bootstrap/knot-backup.sh" --root "$unsafe_root" >/dev/null 2>&1; then
    fail "knot-backup allowed scaffold backup remote"
  else
    ok "knot-backup rejects scaffold backup remote"
  fi

  local runtime_root
  runtime_root="$tmp_parent/runtime-root"
  mkdir -p "$runtime_root/runtime/weixin/bin"
  printf '#!/usr/bin/env bash\n' > "$runtime_root/runtime/weixin/bin/cc-connect"
  printf '#!/usr/bin/env bash\n' > "$runtime_root/runtime/weixin/run-weixin.sh"
  chmod +x "$runtime_root/runtime/weixin/bin/cc-connect" "$runtime_root/runtime/weixin/run-weixin.sh"
  cat > "$runtime_root/runtime/weixin/config.weixin.toml" <<'EOF'
[[projects]]
name = "knot"

[projects.knot_workspace]
enabled = true
helper = "${KNOT_ROOT}/bootstrap/knot-workspace.sh"
root = "${KNOT_ROOT}"

[[projects.platforms]]
type = "weixin"
EOF
  cat > "$runtime_root/runtime/weixin/.env" <<EOF
KNOT_ROOT=$runtime_root
WEIXIN_ALLOW_FROM=*
KNOT_ACTIVE_WORKSPACE=$runtime_root/workspace/users/stale
EOF
  if bash "$ROOT/bootstrap/knot-runtime-check.sh" --root "$runtime_root" --platform weixin >/dev/null 2>&1; then
    fail "knot-runtime-check allowed static KNOT_ACTIVE_WORKSPACE in .env"
  else
    ok "knot-runtime-check rejects static KNOT_ACTIVE_WORKSPACE in .env"
  fi

  local install_root
  install_root="$tmp_parent/install-root"
  mkdir -p "$install_root/.skills/knot-setup" "$install_root/.skills/knot-workflow"
  cp -R "$ROOT/bootstrap" "$install_root/bootstrap"
  cp -R "$ROOT/.skills/knot-setup/references" "$install_root/.skills/knot-setup/references"
  cp "$ROOT/AGENTS.md" "$install_root/AGENTS.md"
  cp "$ROOT/.gitignore" "$install_root/.gitignore"
  printf '%s\n' 'name: knot-workflow' > "$install_root/.skills/knot-workflow/SKILL.md"
  if CODEX_HOME="$install_root/codex-home" bash "$install_root/bootstrap/knot-install.sh" \
    --root "$install_root" \
    --skip-components \
    --skip-build \
    --skip-backup-remote \
    --skip-doctor >/dev/null; then
    if [ -d "$install_root/workspace/users" ] &&
      [ -d "$install_root/runtime" ] &&
      [ -f "$install_root/workspace/admin/permissions.md" ] &&
      [ -f "$install_root/codex-home/AGENTS.md" ] &&
      [ -x "$install_root/bootstrap/knot-workspace.sh" ]; then
      ok "knot-install smoke test creates deterministic local scaffold"
    else
      fail "knot-install smoke test missed expected scaffold files"
    fi
  else
    fail "knot-install smoke test failed"
  fi

  local repair_root
  repair_root="$tmp_parent/repair-root"
  mkdir -p "$repair_root/.skills/knot-setup" \
    "$repair_root/.skills/knot-workflow" \
    "$repair_root/workspace/admin" \
    "$repair_root/codex-home"
  cp -R "$ROOT/bootstrap" "$repair_root/bootstrap"
  cp -R "$ROOT/.skills/knot-setup/references" "$repair_root/.skills/knot-setup/references"
  cp "$ROOT/AGENTS.md" "$repair_root/AGENTS.md"
  cp "$ROOT/.gitignore" "$repair_root/.gitignore"
  printf '%s\n' 'name: knot-workflow' > "$repair_root/.skills/knot-workflow/SKILL.md"
  printf '%s\n' 'custom global instructions' > "$repair_root/codex-home/AGENTS.md"
  printf '%s\n' 'custom permissions' > "$repair_root/workspace/admin/permissions.md"
  printf '%s\n' 'custom feedback' > "$repair_root/workspace/admin/knowledge-feedback.md"
  printf '%s\n' 'custom backup policy' > "$repair_root/workspace/admin/backup-policy.md"

  if CODEX_HOME="$repair_root/codex-home" bash "$repair_root/bootstrap/knot-install.sh" \
    --root "$repair_root" \
    --skip-components \
    --skip-build \
    --skip-backup-remote \
    --skip-doctor >/dev/null &&
    grep -Fq 'custom global instructions' "$repair_root/codex-home/AGENTS.md" &&
    grep -Fq 'custom permissions' "$repair_root/workspace/admin/permissions.md" &&
    grep -Fq 'custom feedback' "$repair_root/workspace/admin/knowledge-feedback.md" &&
    grep -Fq 'custom backup policy' "$repair_root/workspace/admin/backup-policy.md"; then
    ok "knot-install preserves existing global instructions and admin files"
  else
    fail "knot-install overwrote existing global instructions or admin files"
  fi

  : > "$repair_root/codex-home/AGENTS.md"
  if CODEX_HOME="$repair_root/codex-home" bash "$repair_root/bootstrap/knot-install.sh" \
    --root "$repair_root" \
    --skip-components \
    --skip-build \
    --skip-backup-remote \
    --skip-doctor >/dev/null &&
    [ ! -s "$repair_root/codex-home/AGENTS.md" ]; then
    ok "knot-install preserves existing empty global instructions file"
  else
    fail "knot-install overwrote existing empty global instructions file"
  fi

  rm -rf "$tmp_parent" "$unsafe_root"
}

check_any_dir() {
  local label="$1"
  shift

  for path in "$@"; do
    if [ -d "$path" ]; then
      ok "$label: $path"
      return
    fi
  done

  fail "$label missing"
}

check_macos_app() {
  local name="$1"

  if command -v mdfind >/dev/null 2>&1; then
    local found
    found="$(mdfind "kMDItemFSName == '${name}.app'" | head -1)"
    if [ -n "$found" ]; then
      ok "${name}.app: $found"
      return
    fi
  fi

  warn "${name}.app not found by Spotlight"
}

check_skill_file() {
  local path="$1"
  local label="$2"

  if [ -f "$path/SKILL.md" ]; then
    ok "$label: $path"
    return 0
  else
    fail "$label missing SKILL.md: $path"
    return 1
  fi
}

resolve_symlink() {
  local path="$1"
  local target

  target="$(readlink "$path")" || return 1
  case "$target" in
    /*)
      printf '%s\n' "$target"
      ;;
    *)
      (cd "$(dirname "$path")/$target" 2>/dev/null && pwd)
      ;;
  esac
}

check_skill_link() {
  local name="$1"
  local expected="$2"
  local dest="$SKILLS_DIR/$name"
  local resolved

  check_skill_file "$dest" "$name skill" || return

  if [ ! -L "$dest" ]; then
    fail "$name skill is not a symlink: $dest"
    return
  fi

  resolved="$(resolve_symlink "$dest")" || {
    fail "$name skill symlink cannot be resolved: $dest"
    return
  }

  if [ "$resolved" = "$expected" ]; then
    ok "$name skill target: $resolved"
  else
    fail "$name skill points to $resolved, expected $expected"
  fi
}

check_platform() {
  local platform="$1"

  case "$platform" in
    dingtalk|feishu|wecom|weixin)
      if bash "$ROOT/bootstrap/knot-runtime-check.sh" --root "$ROOT" --platform "$platform"; then
        ok "$platform runtime check passed"
      else
        fail "$platform runtime check failed"
      fi
      ;;
    "")
      ;;
    *)
      fail "unknown platform: $platform"
      ;;
  esac
}

check_cc_connect_build() {
  if [ -x "$ROOT/components/cc-connect-local-main/cc-connect" ]; then
    ok "cc-connect build: $ROOT/components/cc-connect-local-main/cc-connect"
  elif [ -x "$ROOT/components/cc-connect-local-main/dist/cc-connect" ]; then
    ok "cc-connect build: $ROOT/components/cc-connect-local-main/dist/cc-connect"
  else
    fail "cc-connect build missing; run make build-noweb in components/cc-connect-local-main"
  fi
}

printf 'Knot doctor\n'
printf 'Root: %s\n\n' "$ROOT"

check_cmd codex
check_macos_app Codex
check_macos_app Obsidian
check_file_exists "$ROOT/.skills/knot-setup/references/codex-agents.template.md" "Codex global AGENTS template"
check_file_exists "$CODEX_HOME_DIR/AGENTS.md" "Codex global AGENTS.md"
if [ -f "$CODEX_HOME_DIR/AGENTS.override.md" ]; then
  warn "Codex global AGENTS.override.md exists and overrides AGENTS.md: $CODEX_HOME_DIR/AGENTS.override.md"
else
  ok "Codex global AGENTS.override.md absent"
fi

printf '\nSkills\n'
check_skill_link "planning-with-files" "$ROOT/components/planning-with-files/.codex/skills/planning-with-files"
check_skill_link "docling-skill" "$ROOT/components/docling-skill/.codex/skills/docling-skill"
check_skill_link "md-for-human" "$ROOT/components/md-for-human/.codex/skills/md-for-human"
check_skill_link "office-xlsx" "$ROOT/components/knot-skills/skills/office-xlsx"
check_skill_link "office-pptx" "$ROOT/components/knot-skills/skills/office-pptx"
check_skill_link "office-docx" "$ROOT/components/knot-skills/skills/office-docx"
check_skill_link "office-pdf" "$ROOT/components/knot-skills/skills/office-pdf"
check_skill_link "web-ppt" "$ROOT/components/knot-skills/skills/web-ppt"
check_skill_link "handoff" "$ROOT/components/handoff-skill/.codex/skills/handoff"
check_skill_link "knot-setup" "$ROOT/.skills/knot-setup"
check_skill_link "knot-workflow" "$ROOT/.skills/knot-workflow"
check_skill_link "wiki-ingest" "$ROOT/components/obsidian-wiki/.skills/wiki-ingest"
check_skill_link "wiki-query" "$ROOT/components/obsidian-wiki/.skills/wiki-query"
check_skill_link "wiki-status" "$ROOT/components/obsidian-wiki/.skills/wiki-status"

printf '\nComponents\n'
check_dir "$ROOT/components/docling-skill/.codex/skills/docling-skill" "docling-skill source"
check_dir "$ROOT/components/md-for-human/.codex/skills/md-for-human" "md-for-human source"
check_dir "$ROOT/components/handoff-skill/.codex/skills/handoff" "handoff source"
check_dir "$ROOT/components/obsidian-wiki" "obsidian-wiki"
check_dir "$ROOT/components/cc-connect-local-main" "cc-connect source"
check_cc_connect_build
check_dir "$ROOT/components/planning-with-files/.codex/skills/planning-with-files" "planning-with-files source"
check_executable "$ROOT/components/knot-skills/scripts/install-codex-skills.sh" "knot-skills installer"
check_dir "$ROOT/components/knot-skills/skills/office-xlsx" "office-xlsx source"
check_dir "$ROOT/components/knot-skills/skills/office-pptx" "office-pptx source"
check_dir "$ROOT/components/knot-skills/skills/office-docx" "office-docx source"
check_dir "$ROOT/components/knot-skills/skills/office-pdf" "office-pdf source"
check_dir "$ROOT/components/knot-skills/skills/web-ppt" "web-ppt source"
check_file_exists "$ROOT/components/knot-skills/skills/office-docx/scripts/dotnet/OfficeDocx.Cli/OfficeDocx.Cli.csproj" "office-docx CLI project"
check_file_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "active user workspace" "web-ppt skill"
check_file_not_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "workspace/deliverables" "web-ppt skill"
check_file_not_contains "$ROOT/components/knot-skills/skills/web-ppt/SKILL.md" "current session" "web-ppt skill"

printf '\nWorkspace\n'
WORKSPACE="$ROOT/workspace"

check_file_contains "$ROOT/.gitignore" ".state/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "workspace/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "runtime/" ".gitignore"
check_file_contains "$ROOT/.gitignore" "components/" ".gitignore"

if [ -e "$ROOT/bootstrap/knot-session.sh" ] || [ -L "$ROOT/bootstrap/knot-session.sh" ]; then
  fail "legacy knot-session helper must be removed"
else
  ok "legacy knot-session helper removed"
fi
check_executable "$ROOT/bootstrap/knot-workspace.sh" "knot-workspace helper"
check_executable "$ROOT/bootstrap/knot-install.sh" "knot-install helper"
check_executable "$ROOT/bootstrap/knot-attachment.sh" "knot-attachment helper"
check_executable "$ROOT/bootstrap/knot-deliver.sh" "knot-deliver helper"
check_executable "$ROOT/bootstrap/knot-backup.sh" "knot-backup helper"
check_executable "$ROOT/bootstrap/knot-runtime-check.sh" "knot-runtime-check helper"
check_file_exists "$ROOT/bootstrap/lib.sh" "bootstrap shell library"
check_file_contains "$ROOT/AGENTS.md" "## Layout" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "components/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "runtime/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Workflow" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "knot-workflow" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/.state/tasks/<task_id>/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Active Workspaces" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-workspace.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "KNOT_ACTIVE_WORKSPACE" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "KNOT_GROUP_WORKSPACE" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/conversations/<platform>/<chat_id>/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Authorization" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/admin/permissions.md" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "access another user's workspace" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Knowledge" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/knowledge/" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "visible diff" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "## Delivery" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-attachment.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "bootstrap/knot-deliver.sh" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "workspace/users/<user_slug>/deliverables" "AGENTS.md"
check_file_contains "$ROOT/AGENTS.md" "cc-connect-attachments" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "## Execution Modes" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "## Backup Automation" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "## Skill Packs" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "Office Pack" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "Agent Workbench" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "Roles:" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "bootstrap/knot-session.sh" "AGENTS.md"
check_file_not_contains "$ROOT/AGENTS.md" "workspace/sessions" "AGENTS.md"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Use the lightest execution weight" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "**quick**" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "**durable**" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "**risky**" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/admin/permissions.md" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "Default to the user-visible result" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-workspace.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-attachment.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-deliver.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-backup.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-runtime-check.sh" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "KNOT_ACTIVE_WORKSPACE" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/conversations/<platform>/<chat_id>/" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "bootstrap/knot-session.sh" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "workspace/sessions" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-ingest skill" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available knowledge-query skill" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-workflow/SKILL.md" "available spreadsheet, document" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-xlsx" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-pptx" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-docx" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "office-pdf" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "web-ppt" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "md-for-human" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "docling-skill" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "wiki-ingest" "knot-workflow"
check_file_not_contains "$ROOT/.skills/knot-workflow/SKILL.md" "wiki-query" "knot-workflow"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/users/<user_slug>/deliverables" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/groups/<group_slug>/deliverables" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ROOT=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "[projects.knot_workspace]" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "Do not set a static agent \`work_dir\`" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "KNOT_ACTIVE_WORKSPACE=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "CC_CONNECT_BIN=" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "components/cc-connect-local-main/cc-connect" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-workspace.sh" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-attachment.sh" "runtime config"
check_file_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-runtime-check.sh" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "\$KNOT_ROOT/workspace/deliverables/example" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "bootstrap/knot-session.sh" "runtime config"
check_file_not_contains "$ROOT/.skills/knot-setup/references/runtime-config.md" "workspace/sessions" "runtime config"

check_dir "$WORKSPACE/knowledge/raw" "knowledge/raw"
check_dir "$WORKSPACE/knowledge/processed" "knowledge/processed"
check_dir "$WORKSPACE/knowledge/vault" "knowledge/vault"
check_dir "$WORKSPACE/users" "users"
check_dir "$WORKSPACE/groups" "groups"
check_dir "$WORKSPACE/conversations" "conversations"
check_dir "$WORKSPACE/admin" "admin"
if [ -e "$WORKSPACE/sessions" ] || [ -L "$WORKSPACE/sessions" ]; then
  fail "legacy workspace/sessions must be removed"
else
  ok "legacy workspace/sessions removed"
fi
if check_file_exists "$WORKSPACE/admin/permissions.md" "permissions"; then
  check_file_contains "$WORKSPACE/admin/permissions.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "agent operating contract, not a security sandbox" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "Platform + Platform User ID" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`operator\`" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`admin\`" "permissions"
  check_file_contains "$WORKSPACE/admin/permissions.md" "\`member\`" "permissions"
fi
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "| User | Workspace | Platform | Platform User ID | Group | Chat ID | Identity Key | Name | Role | Scope | Notes |" "permissions template"
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "Only \`operator\` and \`admin\` may edit this file" "permissions template"
check_file_contains "$ROOT/.skills/knot-setup/references/permissions.template.md" "\`Scope\` is a human-readable boundary" "permissions template"
if check_file_exists "$WORKSPACE/admin/knowledge-feedback.md" "knowledge feedback"; then
  check_file_contains "$WORKSPACE/admin/knowledge-feedback.md" "| Time | Platform | Chat ID | Platform User ID | Identity Key | Name | Topic | Feedback | Evidence | Status | Admin Notes |" "knowledge feedback"
fi
check_file_contains "$ROOT/.skills/knot-setup/references/knowledge-feedback.template.md" "| Time | Platform | Chat ID | Platform User ID | Identity Key | Name | Topic | Feedback | Evidence | Status | Admin Notes |" "knowledge feedback template"
if check_file_exists "$WORKSPACE/admin/backup-policy.md" "backup policy"; then
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "committed and pushed by a Codex app" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "customer-controlled git remote" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "remote \`backup\`" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "realraelrr/knot-agent" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "git add -f" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "Never use broad \`git add -A\`" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "bootstrap/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "bootstrap/knot-backup.sh" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "runtime/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "components/" "backup policy"
  check_file_contains "$WORKSPACE/admin/backup-policy.md" "local secrets" "backup policy"
  check_file_not_contains "$WORKSPACE/admin/backup-policy.md" "legacy" "backup policy"
  check_file_not_contains "$WORKSPACE/admin/backup-policy.md" "- knowledge/" "backup policy"
fi
check_file_not_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "legacy" "backup policy template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "- knowledge/" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "bootstrap/" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "bootstrap/knot-backup.sh" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/backup-policy.template.md" "same URL as \`origin\` or \`scaffold\`" "backup policy template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "bash bootstrap/knot-backup.sh" "backup automation template"
check_file_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "duplicate origin/scaffold remote" "backup automation template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "legacy" "backup automation template"
check_file_not_contains "$ROOT/.skills/knot-setup/references/daily-backup-automation.template.md" "- knowledge/" "backup automation template"
check_backup_remote
run_helper_smoke_tests
check_dir "$ROOT/runtime" "runtime"
check_dir "$WORKSPACE/.state/tasks" ".state/tasks"

if [ -n "$PLATFORMS" ]; then
  printf '\nPlatforms\n'
  warn "platform checks validate local files and required env presence only; credential validity and /whoami authorization require live IM verification"
  OLD_IFS="$IFS"
  IFS=","
  for platform in $PLATFORMS; do
    check_platform "$platform"
  done
  IFS="$OLD_IFS"
else
  printf '\nPlatforms\n'
  warn "no platform checks requested; use --platform dingtalk,feishu,wecom,weixin"
fi

printf '\nDone.\n'

if [ "$FAILURES" -gt 0 ]; then
  printf 'FAILED %s required check(s).\n' "$FAILURES"
  exit 1
fi
