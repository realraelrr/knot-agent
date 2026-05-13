---
name: knot-setup
description: Set up or repair a Knot Codex agent workspace, including component repos, planning-with-files, Codex/Obsidian checks, separated workspace layout, selected IM gateway config, /whoami authorization, and final verification.
---

# Knot Setup

Use this when a Codex agent needs to install, repair, or initialize Knot.
First ask the human for the Knot install root. Do not assume the current
directory is the intended install location.

## Bootstrap Source

Install from the Knot scaffold repository:

```text
https://github.com/realraelrr/knot-agent
```

That repo should contain only the thin scaffold: `AGENTS.md`, `bootstrap/`,
`.skills/`, and safe examples. It must not contain local runtime
secrets, logs, sockets, or customer data.

## Layout

Keep code and agent work separate:

```text
./AGENTS.md
./components/
  docling-skill/
  obsidian-wiki/
  cc-connect-local-main/
  planning-with-files/
  guizang-ppt-skill/
./workspace/
  inbox/
  knowledge/raw/
  knowledge/processed/
  knowledge/vault/
  work/
  deliverables/
  .state/tasks/
./runtime/
```

Do not hard-code machine-specific absolute paths in generated docs or configs
unless a target tool requires an expanded path.

## Workflow

1. Ask for the install root.

Wait for the human to provide a target directory. If the directory is empty or
missing, clone the scaffold into it:

```bash
git clone https://github.com/realraelrr/knot-agent "$INSTALL_ROOT"
cd "$INSTALL_ROOT"
```

If the directory already exists, inspect it first. If it already appears to be a
Knot root, confirm that the human wants to reuse it. Do not overwrite an
existing non-empty directory without explicit approval.

2. Check prerequisites:

```bash
pwd
command -v codex || true
mdfind "kMDItemFSName == 'Codex.app'" | head -1 || true
mdfind "kMDItemFSName == 'Obsidian.app'" | head -1 || true
```

3. Create directories:

```bash
mkdir -p components runtime \
  workspace/inbox \
  workspace/knowledge/raw \
  workspace/knowledge/processed \
  workspace/knowledge/vault \
  workspace/work \
  workspace/deliverables \
  workspace/.state/tasks
```

4. Ensure component repos exist:

```bash
test -d components/docling-skill || git clone https://github.com/realraelrr/docling-skill components/docling-skill
test -d components/obsidian-wiki || git clone https://github.com/Ar9av/obsidian-wiki components/obsidian-wiki
test -d components/cc-connect-local-main || git clone https://github.com/realraelrr/cc-connect components/cc-connect-local-main
test -d components/planning-with-files || git clone https://github.com/realraelrr/planning-with-files components/planning-with-files
test -d components/guizang-ppt-skill || git clone https://github.com/realraelrr/guizang-ppt-skill components/guizang-ppt-skill
```

`components/` is the local source of truth for component-provided skills.
Scaffold-owned skills live under `.skills/`. `$HOME/.codex/skills` should
contain links to those source locations, not independent editable copies.

5. Link required skills into Codex:

```bash
mkdir -p "$HOME/.codex/skills"

link_skill() {
  name="$1"
  target="$(cd "$2" && pwd)"
  dest="$HOME/.codex/skills/$name"

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

link_skill docling-skill components/docling-skill
link_skill planning-with-files components/planning-with-files/.codex/skills/planning-with-files
link_skill guizang-ppt-skill components/guizang-ppt-skill
find components/obsidian-wiki/.skills -mindepth 1 -maxdepth 1 -type d -exec sh -c '
  link_skill() {
    name="$1"
    target="$(cd "$2" && pwd)"
    dest="$HOME/.codex/skills/$name"
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
  }
  for d do link_skill "$(basename "$d")" "$d"; done
' sh {} +
test -d .skills/knot-setup && link_skill knot-setup .skills/knot-setup
test -d .skills/knot-workflow && link_skill knot-workflow .skills/knot-workflow
```

This intentionally backs up existing non-symlink skill directories before
linking. The component copy should be the active source of truth.

6. Configure `AGENTS.md`.

If `AGENTS.md` is missing, create it from
`./.skills/knot-setup/references/AGENTS.template.md`. If the template is not
present, create a concise `AGENTS.md` that defines:

- Codex starts from the Knot root.
- Code lives in `components/`.
- User and agent work lives in `workspace/`.
- Complex task state goes under `workspace/.state/tasks/<task_id>/`.
- Knowledge conversion and wiki ingest are decoupled.
- Knot workflow routing uses `knot-workflow`.
- IM attachments use `cc-connect-attachments`.
- Material knowledge changes require human approval or a visible diff.

7. Build `cc-connect`:

```bash
pushd components/cc-connect-local-main
make build-noweb
./dist/cc-connect --version
popd
```

8. Ask which IM platforms to configure.

Do not configure every platform by default. Ask the human to choose one or more:

```text
dingtalk
feishu
wecom
weixin
```

For each chosen platform:

- create or reuse the matching config under `runtime/`;
- create `.env` placeholders when credentials are missing;
- copy `components/cc-connect-local-main/dist/cc-connect` into the selected
  runtime `bin/` directory;
- ask the human to fill platform credentials;
- start only that platform gateway;
- ask the human to send `/whoami` from every intended context.

Read `./.skills/knot-setup/references/runtime-config.md` for platform config
templates, credential keys, run scripts, and `/whoami` field mapping.

9. Complete `/whoami` authorization.

For each intended direct chat or group, collect the full `/whoami` response:

```text
User ID
Name
Platform
Chat ID
Session Key
```

Update the relevant allow/admin config, restart the gateway, and ask the human
to verify from that exact context. Repeat until every intended context passes.

10. Final verification:

```bash
bash bootstrap/doctor.sh
bash bootstrap/doctor.sh --platform dingtalk
```

Run the platform-specific doctor once for each configured platform. Also verify
each configured IM with:

- `/whoami` returns the expected identity;
- a normal message receives a Codex reply;
- image/file send-receive works if the platform is expected to support it.

## Completion Report

Report only:

- component repos installed or reused;
- Codex CLI, Codex app, and Obsidian app detection result;
- skills linked, including `knot-workflow`, `planning-with-files`, and
  `guizang-ppt-skill`;
- `AGENTS.md` created or preserved;
- `cc-connect` build/version result;
- IM platforms configured;
- `/whoami` contexts authorized;
- verification commands and pass/fail status.
