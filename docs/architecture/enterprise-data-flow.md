# Enterprise Data Flow

Knot is a thin local harness around Codex. It does not replace enterprise
systems of record; it defines where enterprise inputs enter the agent workspace,
where outputs may leave, and which deterministic boundary events are recorded.

## Flow Classes

| Flow | Input | Knot control point | Output |
|---|---|---|---|
| IM message flow | Group or direct messages from a configured IM platform | IM glue layer resolves identity and launches Codex from the active user workspace | A Codex session in `workspace/users/<user_slug>/`, with optional current group workspace context |
| File flow | Uploaded files, generated files, and agent-created artifacts | Workspace layout plus `bin/knot-deliver.sh` and `bin/knot-attachment.sh` enforce deliverables boundaries | Local deliverables and optional IM attachment blocks from authorized `deliverables/` directories |
| Knowledge flow | Approved sources, admin feedback, and reviewed corrections | Admin approval, visible diff, and `workspace/admin/knowledge-feedback.md` | Durable shared knowledge under `workspace/knowledge/` |
| Audit flow | Deterministic boundary actions from Knot helpers | `bin/knot-audit.sh` writes compact rows that follow `docs/schemas/audit-event.schema.json` | `events.jsonl` records under `workspace/conversations/<platform>/chat_<hash>/` |

## Boundary Rules

- IM conversation directories are source and audit metadata, not Codex working
  directories or delivery directories.
- Generated files are not user-visible delivery until they are copied into the
  active user or authorized current group `deliverables/` directory.
- Durable knowledge changes require human review; feedback alone is not a
  verified fact.
- Audit rows record compact boundary evidence. Codex session history remains
  the transcript source of truth for the full conversation.

## Out Of Scope

Knot does not provide OS tenant isolation, enterprise DLP, live platform
credential authorization, or a replacement for customer systems of record.
Those controls belong to the deployment environment described in
`docs/security/security-model.md` and `docs/ops/deployment-inputs.md`.
