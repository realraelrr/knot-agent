# Enterprise Data Flow

Knot is a thin local harness around Codex. It does not replace enterprise
systems of record; it defines where enterprise inputs enter the agent workspace,
where outputs may leave, and which deterministic boundary events are recorded.

## Flow Classes

| Flow | Input | Knot control point | Output |
|---|---|---|---|
| IM message flow | Group or direct messages from a configured IM platform | IM glue layer resolves identity and launches Codex from the direct user workspace or authorized current group workspace | A Codex session in `workspace/users/<user_slug>/` for direct chats, or `workspace/groups/<group_slug>/` for group chats |
| File flow | Uploaded files, generated files, and agent-created artifacts | Workspace layout plus `bin/knot-deliver.sh` and `bin/knot-attachment.sh` enforce scope-specific deliverables boundaries | Local deliverables and optional IM attachment blocks from the current direct user or authorized group `deliverables/` directory |
| Knowledge flow | Approved sources, admin feedback, and reviewed corrections | GitHub branch protection, explicit admin review, visible diff, local proposal bundles, and `workspace/admin/knowledge-feedback.md` | Durable shared knowledge on the approved `main` ref, mirrored locally under `workspace/knowledge/vault/` by default |
| Audit flow | Deterministic boundary actions from Knot helpers | `bin/knot-audit.sh` writes compact rows that follow `docs/schemas/audit-event.schema.json` | `events.jsonl` records under `workspace/conversations/<platform>/chat_<hash>/` |

## Boundary Rules

- IM conversation directories are source and audit metadata, not Codex working
  directories or delivery directories.
- Generated files are not user-visible delivery until they are copied into the
  active direct user or authorized current group `deliverables/` directory.
- Group-chat sessions run from the shared group workspace. Drafts and task
  state should be written to the stable actor lane under
  `workspace/groups/<group_slug>/work/<user_slug>/`; this is an agent protocol,
  not OS-level write isolation.
- Durable knowledge changes require explicit admin review; feedback alone is
  not a verified fact. Members should create local proposal bundles, never
  write the approved mirror directly.
- Knot runtime reads only the approved knowledge mirror or a pinned approved
  commit. Local proposal bundles and unapproved refs are not durable knowledge
  sources.
- Audit rows record compact boundary evidence. Codex session history remains
  the transcript source of truth for the full conversation.

## Out Of Scope

Knot does not provide OS tenant isolation, enterprise DLP, live platform
credential authorization, or a replacement for customer systems of record.
Those controls belong to the deployment environment described in
`docs/security/security-model.md` and `docs/ops/deployment-inputs.md`.
