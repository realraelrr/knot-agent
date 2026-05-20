---
name: knot-setup
description: Set up or repair a Knot Codex agent workspace with the deterministic installer, global Codex defaults, project boundaries, selected IM runtime config, /whoami authorization, and final verification.
---

# Knot Setup

Use this when a Codex agent needs to install, repair, or initialize Knot.
This skill is a thin human-decision wrapper around deterministic helper
scripts. Do not duplicate install logic here when a helper already owns it.

## Source

Install from the Knot scaffold repository:

```text
https://github.com/realraelrr/knot-agent
```

The scaffold should contain only safe project source and setup templates:
`AGENTS.md`, `bootstrap/`, `.skills/`, docs, and examples. It must not contain
runtime secrets, logs, sockets, or customer data.

## Workflow

1. Ask for the install root.

Do not assume the current directory is the intended root. If the directory is
missing or empty, clone the scaffold into it:

```bash
git clone https://github.com/realraelrr/knot-agent "$INSTALL_ROOT"
cd "$INSTALL_ROOT"
if git remote get-url origin 2>/dev/null | grep -q 'realraelrr/knot-agent'; then
  git remote rename origin scaffold
fi
```

If the directory already exists, inspect it first. Reuse it only when it is a
Knot root or the human explicitly confirms reuse. Do not overwrite a non-empty
unrelated directory.

2. Decide backup remote.

Ask for a customer-controlled git remote URL or local bare repo path to use as
the `backup` remote. Do not use the Knot scaffold remote as backup. If no
backup remote is available, continue only with `--skip-backup-remote` and
report that daily rollback backup is not ready.

3. Run the deterministic installer.

The installer owns directory creation, admin templates, global Codex defaults,
project `AGENTS.md`, component repos, skill links, helper permissions,
`cc-connect` build, and the base doctor check.

```bash
bash bootstrap/knot-install.sh --backup-remote "$BACKUP_REMOTE_URL"
```

When intentionally proceeding without backup setup:

```bash
bash bootstrap/knot-install.sh --skip-backup-remote
```

For repair work, use the same installer. It should preserve existing global
Codex instructions and local admin files unless a file is missing.

4. Configure selected IM platforms.

Do not configure every platform by default. Ask the human which platforms to
enable:

```text
dingtalk
feishu
wecom
weixin
```

For each selected platform, read only the relevant section of
`./.skills/knot-setup/references/runtime-config.md`, then:

- create or reuse the matching config under `runtime/`;
- create credential placeholders when credentials are missing;
- point the platform config at the built `cc-connect` binary;
- run `bash bootstrap/knot-runtime-check.sh --platform PLATFORM`;
- start only that platform gateway;
- ask the human to send `/whoami` from each intended direct or group context.

5. Complete `/whoami` authorization.

For each intended direct chat or group, collect the full `/whoami` response:

```text
User ID
Name
Platform
Chat ID
Identity Key
```

Update only the relevant authorization/admin config, restart the gateway, and
ask the human to verify from that exact context. Repeat until every intended
context passes.

6. Final verification.

Always run:

```bash
bash bootstrap/doctor.sh
```

For each configured platform, also run:

```bash
bash bootstrap/doctor.sh --platform <configured-platform>
```

Verify each configured IM context with:

- `/whoami` returns the expected identity;
- a normal message receives a Codex reply;
- image or file send-receive works when the platform is expected to support it;
- `git remote get-url backup` is configured and does not point to the scaffold,
  unless setup intentionally used `--skip-backup-remote`;
- the Codex app daily backup automation is created from
  `./.skills/knot-setup/references/daily-backup-automation.template.md`.

## Completion Report

Report only:

- install root and whether it was cloned, reused, or repaired;
- installer command and pass/fail result;
- backup remote and daily backup automation status;
- global Codex `AGENTS.md` installed, matched, or preserved;
- project `AGENTS.md` created or preserved;
- admin templates created or preserved;
- component, skill-link, and `cc-connect` build status from the installer;
- IM platforms configured;
- `/whoami` contexts authorized;
- final verification commands and pass/fail status.
