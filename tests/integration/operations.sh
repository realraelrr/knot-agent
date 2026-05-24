# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Depends on workspace.sh creating the shared smoke workspace.
UNSAFE_ROOT="$(mktemp -d)"
git -C "$UNSAFE_ROOT" init >/dev/null 2>&1
git -C "$UNSAFE_ROOT" remote add backup https://github.com/realraelrr/knot-agent.git
if bash "$ROOT/bin/knot-backup.sh" --root "$UNSAFE_ROOT" >/dev/null 2>&1; then
  fail "knot-backup allowed scaffold backup remote"
else
  ok "knot-backup rejects scaffold backup remote"
fi

runtime_root="$TMP_PARENT/runtime-root"
mkdir -p "$runtime_root/runtime/weixin/bin"
printf '#!/usr/bin/env bash\n' > "$runtime_root/runtime/weixin/bin/cc-connect"
printf '#!/usr/bin/env bash\n' > "$runtime_root/runtime/weixin/run-weixin.sh"
chmod +x "$runtime_root/runtime/weixin/bin/cc-connect" "$runtime_root/runtime/weixin/run-weixin.sh"
cat > "$runtime_root/runtime/weixin/config.weixin.toml" <<'EOF'
[[projects]]
name = "knot"

[projects.knot_workspace]
enabled = true
helper = "${KNOT_ROOT}/bin/knot-workspace.sh"
root = "${KNOT_ROOT}"

[[projects.platforms]]
type = "weixin"
EOF
cat > "$runtime_root/runtime/weixin/.env" <<EOF
KNOT_ROOT=$runtime_root
WEIXIN_ALLOW_FROM=*
KNOT_ACTIVE_WORKSPACE=$runtime_root/workspace/users/stale
EOF
if bash "$ROOT/bin/knot-runtime-check.sh" --root "$runtime_root" --platform weixin >/dev/null 2>&1; then
  fail "knot-runtime-check allowed static KNOT_ACTIVE_WORKSPACE in .env"
else
  ok "knot-runtime-check rejects static KNOT_ACTIVE_WORKSPACE in .env"
fi
