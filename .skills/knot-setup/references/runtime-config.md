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
    config.weixin.toml
    run-weixin.sh
```

Copy the built gateway binary after `make build-noweb`:

```bash
# dingtalk, feishu, or wecom
mkdir -p runtime/dingtalk-feishu-wecom/bin
cp components/cc-connect-local-main/dist/cc-connect runtime/dingtalk-feishu-wecom/bin/cc-connect

# weixin
mkdir -p runtime/weixin/bin
cp components/cc-connect-local-main/dist/cc-connect runtime/weixin/bin/cc-connect
```

Run only the block needed for the selected platform. Create config files and run
scripts only for selected platforms.

## Shared Config Skeleton

Use the Knot root as the gateway working directory. Use expanded absolute paths
inside cc-connect config files when required by cc-connect.

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

[[projects]]
name = "knot"

[projects.agent]
type = "codex"

[projects.agent.options]
work_dir = "${KNOT_ROOT}"
app_server_url = "stdio"
mode = "suggest"

[[projects.platforms]]
name = "PLATFORM"
type = "PLATFORM"
```

Set `KNOT_ROOT` in the runtime environment to the install root. If cc-connect
does not expand `KNOT_ROOT` in a field, the installing agent should write the
expanded install root into the generated config file at install time.

## Platform Credentials

Put secrets in `.env`, not in committed config.

```bash
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
- load `.env` if present;
- fail if required credentials are missing;
- execute `bin/cc-connect --config config.PLATFORM.toml`;
- write logs inside the selected runtime directory.

Example:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
test -f .env && set -a && . ./.env && set +a
exec ./bin/cc-connect --config config.PLATFORM.toml
```

## Authorization

- Do not assume one user ID authorizes every context.
- Collect `/whoami` separately for each direct chat or group that should use
  the agent.
- Add only the required `User ID`, `Chat ID`, or `Session Key` entries.
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

## Attachments

Use strict attachment blocks when Codex must send files through IM:

````text
```cc-connect-attachments
image: $KNOT_ROOT/workspace/deliverables/example.png
file: $KNOT_ROOT/workspace/deliverables/example.pdf
```
````

Use paths that the gateway process can read. If a platform cannot send or
receive a given attachment type, treat it as gateway capability work.
