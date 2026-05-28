# Runtime Config

Read this only while configuring selected IM gateways.

Use only the platforms selected by the human. Do not configure every platform
by default.

## Runtime Shape

```text
./runtime/
  dingtalk-feishu-wecom/
    bin/cc-connect
    .env
    config.dingtalk.toml
    config.feishu.toml
    config.wecom.toml
    run-dingtalk.sh
    run-feishu.sh
    run-wecom.sh
  weixin/
    bin/cc-connect
    .env
    config.weixin.toml
    run-weixin.sh
```

Copy the built gateway binary after `make build-noweb`:

```bash
CC_CONNECT_BIN=""
if [ -x components/cc-connect-local-main/cc-connect ]; then
  CC_CONNECT_BIN="components/cc-connect-local-main/cc-connect"
elif [ -x components/cc-connect-local-main/dist/cc-connect ]; then
  CC_CONNECT_BIN="components/cc-connect-local-main/dist/cc-connect"
else
  echo "cc-connect binary not found; run make build-noweb in components/cc-connect-local-main" >&2
  exit 1
fi

# dingtalk, feishu, or wecom
mkdir -p runtime/dingtalk-feishu-wecom/bin
cp "$CC_CONNECT_BIN" runtime/dingtalk-feishu-wecom/bin/cc-connect

# weixin
mkdir -p runtime/weixin/bin
cp "$CC_CONNECT_BIN" runtime/weixin/bin/cc-connect
```

Run only the block needed for the selected platform. Create config files and run
scripts only for selected platforms.

## Shared Config Skeleton

Use the Knot root as the gateway install/runtime root. Enable cc-connect's
Knot resolver so each incoming message calls `bin/knot-workspace.sh`
before agent startup. Do not set a static agent `work_dir`; the resolver starts
Codex from the returned `KNOT_ACTIVE_WORKSPACE` and injects the other `KNOT_*`
context exports into the agent process.

```toml
data_dir = "${HOME}/.cc-connect/knot-PLATFORM"

[log]
level = "info"

[display]
mode = "quiet"

[instant_reply]
enabled = true
initial = "收到啦，我开始处理。"
superseded = "好的，我补充一下。"
queued = "收到，排在当前任务后处理。"

[queue]
mode = "interrupt"
max_depth = 5

# Optional hard cap for one agent turn. cc-connect also has idle_timeout_mins,
# but that timer resets on tool events; max_turn_time_mins does not.
# Enable this when long-running commands can otherwise keep a session busy.
# max_turn_time_mins = 60

[[projects]]
name = "knot"

[projects.agent]
type = "codex"

[projects.knot_workspace]
enabled = true
helper = "${KNOT_ROOT}/bin/knot-workspace.sh"
root = "${KNOT_ROOT}"

[projects.agent.options]
backend = "app_server"
app_server_url = "stdio://"
mode = "suggest"

[[projects.platforms]]
name = "PLATFORM"
type = "PLATFORM"
```

Set `KNOT_ROOT` in the runtime environment to the install root. The helper
produces `KNOT_ACTIVE_WORKSPACE` per message; it should not be written into
`.env` or used as a static cc-connect config placeholder.

## Platform Credentials

Put secrets in `.env`, not in committed config.

```bash
KNOT_ROOT=

# DingTalk
DINGTALK_CLIENT_ID=
DINGTALK_CLIENT_SECRET=
DINGTALK_ROBOT_CODE=
DINGTALK_ALLOW_FROM=

# Feishu
FEISHU_APP_ID=
FEISHU_APP_SECRET=
FEISHU_ALLOW_FROM=
FEISHU_ALLOW_CHAT=

# WeCom
WECOM_BOT_ID=
WECOM_BOT_SECRET=
WECOM_ALLOW_FROM=

# Weixin
WEIXIN_ALLOW_FROM=
```

Platform config snippets:

```toml
# dingtalk
[projects.platforms.options]
client_id = "${DINGTALK_CLIENT_ID}"
client_secret = "${DINGTALK_CLIENT_SECRET}"
robot_code = "${DINGTALK_ROBOT_CODE}"
allow_from = "${DINGTALK_ALLOW_FROM}"
```

```toml
# feishu
[projects.platforms.options]
app_id = "${FEISHU_APP_ID}"
app_secret = "${FEISHU_APP_SECRET}"
allow_from = "${FEISHU_ALLOW_FROM}"
allow_chat = "${FEISHU_ALLOW_CHAT}"
enable_feishu_card = false
```

```toml
# wecom
[projects.platforms.options]
mode = "websocket"
bot_id = "${WECOM_BOT_ID}"
bot_secret = "${WECOM_BOT_SECRET}"
allow_from = "${WECOM_ALLOW_FROM}"
```

```toml
# weixin
[projects.platforms.options]
allow_from = "${WEIXIN_ALLOW_FROM}"
base_url = "https://ilinkai.weixin.qq.com"
```

## Run Scripts

Each run script should:

- `cd` to its runtime directory;
- load `.env`;
- fail if required credentials are missing;
- execute `bin/cc-connect --config config.PLATFORM.toml`;
- write logs inside the selected runtime directory.

Example:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
test -f .env || { echo ".env missing" >&2; exit 1; }
set -a && . ./.env && set +a
exec ./bin/cc-connect --config config.PLATFORM.toml
```

Before starting a selected platform, run:

```bash
bash bin/knot-runtime-check.sh --platform PLATFORM
```

This is a static preflight only. It does not start cc-connect, call `/whoami`,
or verify live IM authorization.

## Authorization

- Do not assume one user ID authorizes every context.
- Collect `/whoami` separately for each direct chat or group that should use
  the agent.
- Add only the required `User ID`, `Chat ID`, or `Identity Key` entries.
- Restart the selected gateway after config changes.

Field mapping:

```text
dingtalk: use User ID in DINGTALK_ALLOW_FROM.
feishu: use User ID in FEISHU_ALLOW_FROM; use Chat ID in FEISHU_ALLOW_CHAT for group-specific authorization.
wecom: use User ID in WECOM_ALLOW_FROM.
weixin: use User ID in WEIXIN_ALLOW_FROM.
```

If a platform supports comma-separated allow lists, append new entries without
removing existing approved contexts. If the config requires a different format,
inspect the local cc-connect docs/source and preserve the platform's expected
syntax.

## Workspace And Attachments

Use `bin/knot-workspace.sh` as a preflight helper after cc-connect or
another IM glue layer has parsed platform, user, and optional group metadata.
The helper prints source-safe shell exports. Start Codex with cwd set to
`KNOT_ACTIVE_WORKSPACE`:

```bash
eval "$(bash bin/knot-workspace.sh \
  --platform PLATFORM \
  --user-id USER_ID \
  --user-slug USER_SLUG \
  --chat-id CHAT_ID \
  --identity-key IDENTITY_KEY)"
cd "$KNOT_ACTIVE_WORKSPACE"
```

Add `--group-slug GROUP_SLUG` and `--group-name GROUP_NAME` only for authorized
group chat contexts.

For direct chats, `KNOT_SCOPE=direct` and `KNOT_ACTIVE_WORKSPACE` is the actor
user workspace. For authorized group chats, `KNOT_SCOPE=group`,
`KNOT_ACTIVE_WORKSPACE` and `KNOT_SCOPE_WORKSPACE` are the current group
workspace, and `KNOT_ACTOR_WORKSPACE` is
`workspace/groups/<group_slug>/work/<user_slug>` for drafts and task state.
This actor lane is an agent protocol, not OS-level write isolation.

`KNOT_CONVERSATION_DIR` is source/audit metadata only and must not be used as a
work or deliverables directory.

Use `bin/knot-attachment.sh` when Codex must send files through IM. It
validates that the file exists under the current direct user's
`deliverables/` directory, or under the current group `deliverables/` directory
in group scope, and prints a strict attachment block:

````text
```cc-connect-attachments
image: $KNOT_ROOT/workspace/users/<user_slug>/deliverables/example.png
file: $KNOT_ROOT/workspace/groups/<group_slug>/deliverables/example.pdf
```
````

Use paths that the gateway process can read. If a platform cannot send or
receive a given attachment type, treat it as gateway capability work.
