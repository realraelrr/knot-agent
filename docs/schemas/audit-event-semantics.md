# Audit Event Semantics

`docs/schemas/audit-event.schema.json` defines the event row shape. This file
defines what each event means and which component is responsible for writing it.

## Principles

- Audit events are compact boundary evidence, not transcripts.
- Codex session history remains the user/model conversation source of truth.
- Helpers write events only for deterministic boundary checks they perform.
- cc-connect/runtime writes events for real platform send results.
- Resource events should include `resource_kind`, `resource_path`,
  `resource_sha256`, and `resource_size_bytes` when a concrete file or inbound
  attachment is available.

## Workspace Routing

Lifecycle:

```text
conversation.initialized
group.access.allowed | group.access.denied
```

Writer:

- `bin/knot-workspace.sh` writes `conversation.initialized` when explicitly
  asked to initialize conversation audit state.
- workspace and delivery helpers may write `group.access.allowed` or
  `group.access.denied` when group authorization is part of the action.

Required fields:

- `platform`
- `chat_id_hash`
- `platform_user_id_hash` when known
- `identity_key_hash` when known
- `actor_user` when resolved
- `group_slug` for group scope
- `reason_code` for denied events

## Delivery

Lifecycle:

```text
delivery.verified -> delivery.sent | delivery.failed
delivery.denied
```

Writers:

- `bin/knot-attachment.sh` writes `delivery.verified` after validating that an
  attachment block path is inside the current direct user or authorized group
  `deliverables/` directory.
- `bin/knot-deliver.sh` writes `delivery.denied` when copying into
  deliverables is refused.
- cc-connect/runtime writes `delivery.sent` only after the platform sender
  succeeds.
- cc-connect/runtime writes `delivery.failed` when the final send path,
  file read, file stability, or platform send fails.

Reason codes:

- `outside_deliverables`: path is outside the active direct/group deliverables
  boundary.
- `conversation_source_denied`: source path is under `workspace/conversations/`.
- `unauthorized_group`: group context is missing, ambiguous, or not authorized.
- `symlink_denied`: workspace, deliverables, or attachment path includes a
  symlink escape.
- `hardlink_denied`: delivery source or outbound attachment has multiple hard
  links and is refused.
- `invalid_resource`: file is missing, unsupported, or otherwise invalid.
- `attachment_read_failed`: cc-connect/runtime could not read the file before
  sending.
- `attachment_hash_mismatch`: cc-connect/runtime detected file instability
  while preparing the send.
- `send_failed`: the platform send operation failed or the platform does not
  support the requested attachment kind.

## Knowledge

Lifecycle:

```text
proposed -> reviewed -> applied | denied
```

The default Knot audit schema does not currently emit all knowledge lifecycle
events. Knowledge proposals are represented by local proposal bundles, GitHub
pull requests, protected branch history, and `workspace/admin/knowledge-feedback.md`.

Rules:

- members may create proposal bundles;
- only explicit admins approve durable knowledge;
- approved knowledge is read from the protected `main` ref or a pinned approved
  commit, mirrored locally under `workspace/knowledge/vault/`.

## Working Style

Lifecycle:

```text
working_style.pack.generated | working_style.pack.denied
working_style.patch.applied | working_style.patch.denied
```

Writers:

- `bin/knot-working-style-pack.sh`
- `bin/knot-working-style-apply.sh`

Meaning:

- pack events describe creation or denial of the session-start read-only
  `style.md` snapshot;
- patch events describe deterministic application or refusal of a proposed
  update to the actor's `style.md`.

## Recovery

Lifecycle:

```text
recovery.prompt_sent -> recovery.completed | recovery.failed
```

Writer:

- cc-connect/runtime writes these events when the agent returns an empty response
  and the recovery prompt is sent.

Meaning:

- `recovery.prompt_sent`: runtime asked the agent to repair an empty response.
- `recovery.completed`: the recovery turn produced visible text or a delivery.
- `recovery.failed`: the recovery turn did not produce a usable result.
