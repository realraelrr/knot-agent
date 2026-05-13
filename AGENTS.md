# Knot Agent Workspace

Codex sessions for Knot start from this directory.

## Layout

```text
components/   source repos and reusable code
runtime/      IM gateway configs, run scripts, logs, sockets, local secrets
workspace/    user files, knowledge, drafts, deliverables, task state
```

Use `workspace/` for agent work:

```text
workspace/inbox/                 user-supplied inputs
workspace/knowledge/raw/         approved long-term sources
workspace/knowledge/processed/   sidecars, OCR, extracted intermediates
workspace/knowledge/vault/       Obsidian vault
workspace/work/                  drafts and reusable working assets
workspace/deliverables/          final files for users
workspace/.state/tasks/          recoverable task/session state
```

Do not put temporary plans, generated files, downloads, or outputs in the root.

## Task State

Use `planning-with-files` for complex work. Isolate each task under:

```text
workspace/.state/tasks/<task_id>/
  task_plan.md
  findings.md
  progress.md
  files/
```

Use task ids like:

```text
YYYYMMDD-HHMMSS-channel-short-topic
```

## Workflow Routing

Use `knot-workflow` before Knot tasks that involve knowledge, IM, attachments,
generated files, or multi-step delivery. Let it choose the next skill or tool;
do not duplicate detailed workflow rules here.

## Knowledge Work

- Use `docling-skill` for document conversion.
- Use `obsidian-wiki` skills for ingest, query, status, lint, and update.
- Use `guizang-ppt-skill` when creating magazine-style or e-ink HTML/PPT
  presentation deliverables.
- Keep conversion and wiki ingest decoupled.
- Treat feedback as a signal, not verified fact.
- Require human approval or a visible diff before material knowledge changes.

## IM Attachments

Text replies are delivered by `cc-connect`.

When sending a local file or image through IM, use:

````text
```cc-connect-attachments
image: $KNOT_ROOT/workspace/deliverables/example.png
file: $KNOT_ROOT/workspace/deliverables/example.pdf
```
````

Do not answer with only a local path when the user asked to send the file.
