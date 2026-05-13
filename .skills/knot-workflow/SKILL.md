---
name: knot-workflow
description: Route Knot workspace tasks that involve knowledge ingestion, wiki updates, IM-agent work, attachments, generated files, deliverables, or multi-step execution; coordinate docling-skill, obsidian-wiki skills, cc-connect, planning-with-files, and guizang-ppt-skill when needed.
---

# Knot Workflow

Use this skill to route Knot tasks. Keep the individual skills independent:
Codex coordinates them; the skills do not depend on each other.

## First Decision

Classify the request before acting:

- **Knowledge source**: a document, folder, note, URL, or attachment should become reusable knowledge.
- **Knowledge query**: the user asks what the organization knows or what a source says.
- **Execution task**: the user wants analysis, drafting, PPT, HTML, file generation, research, automation, or operations work.
- **IM delivery**: the user wants a local file or image sent back through chat.
- **Complex task**: the task needs recovery, multiple steps, or cross-file work.

## Routing

- Raw document to knowledge: use `docling-skill` when conversion helps, write
  intermediates under `workspace/knowledge/processed/`, then use
  `wiki-ingest` for durable knowledge.
- Direct knowledge ingest: use `wiki-ingest` when the source is already clean
  text or Markdown. Do not force a docling step.
- Knowledge query: use `wiki-query` first. If evidence is missing or stale,
  say so and, when allowed, propose a feedback or update path.
- Wiki maintenance: use obsidian-wiki skills such as `wiki-status`,
  `wiki-lint`, `wiki-update`, or `wiki-digest` only when the task calls for
  them.
- Presentation deliverable: use `guizang-ppt-skill`; write final outputs under
  `workspace/deliverables/`.
- Simple execution: if no specialized skill or recoverable task state is
  needed, do the work directly and place drafts, inputs, and outputs in the
  matching `workspace/` location.
- Complex execution: use `planning-with-files`; isolate task state under
  `workspace/.state/tasks/<task_id>/`.
- IM file/image delivery: use the cc-connect attachment block. Do not answer
  with only a local path when the user asked to receive the file in IM.

## Storage Rules

- User inputs go under `workspace/inbox/` unless they are already in place.
- Approved long-term sources go under `workspace/knowledge/raw/`.
- Extracted sidecars and OCR outputs go under `workspace/knowledge/processed/`.
- Final user-facing files go under `workspace/deliverables/`.
- Drafts and reusable working assets go under `workspace/work/`.
- Do not put temporary work in the Knot root.

## Boundaries

- The wiki is memory and reference material, not the boundary of what Codex can
  do.
- Do not turn Knot into a static pipeline. Choose the shortest reliable path
  for the request.
- Keep conversion and wiki ingest decoupled.
- Treat feedback as a signal, not verified fact.
- Require human approval or a visible diff before material knowledge changes.
