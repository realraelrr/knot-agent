---
name: knot-memory
description: Use when a Knot task depends on actor working memory, memory-pack context, cross-platform IM memory continuity, or memory update planning.
---

# Knot Memory

## Boundary

Knot memory stays inside Knot. It is not a separate plugin, database, agent
runtime, or replacement for Codex session history.

This skill tells Codex how to use memory context. Deterministic enforcement
lives in Knot helpers and tests, especially `bin/knot-memory-pack.sh`.

## Current Runtime Contract

Direct-chat memory-pack generation and validated memory-patch apply are
implemented.

- Source of truth: `workspace/users/<user_slug>/memory/`.
- Runtime context: `workspace/users/<user_slug>/.knot/memory-pack.md`.
- Audit target: `workspace/conversations/<platform>/chat_<hash>/events.jsonl`.
- Write targets shown in the pack may be proposed by Codex and applied only
  through the deterministic apply helper.

Group memory packs, restricted block filtering, and wiki promotion are
design-stage capabilities. Do not claim they are available until their
deterministic helpers exist.

## Agent Usage

If `.knot/memory-pack.md` exists in the active workspace, read it before doing
memory-sensitive work.

If memory is needed and the pack is missing, generate it through the helper
using resolved Knot runtime context:

```bash
bash "$KNOT_ROOT/bin/knot-memory-pack.sh" pack \
  --root "$KNOT_ROOT" \
  --platform "$KNOT_PLATFORM" \
  --chat-id "$KNOT_CHAT_ID" \
  --user-id "$KNOT_PLATFORM_USER_ID" \
  --identity-key "$KNOT_IDENTITY_KEY" \
  --actor-user "$KNOT_ACTOR_USER" \
  --active-workspace "$KNOT_ACTIVE_WORKSPACE" \
  --user-workspace "$KNOT_USER_WORKSPACE" \
  --conversation-dir "$KNOT_CONVERSATION_DIR"
```

If the helper denies memory, do not bypass it by reading memory files directly.
Continue only when the task does not require memory; otherwise report that
memory context is unavailable.

## Content Rules

- Use working memory as context, not verified enterprise fact.
- Durable business knowledge belongs in `workspace/knowledge/`.
- `profile.md` is read-only runtime context, not a normal patch target.
- Do not copy raw transcripts, secrets, or source documents into memory.
- Do not mention memory helper names, local paths, session internals, or pack
  details in normal user-facing IM replies.

## Memory Updates

Codex may draft `.knot/memory-patch.md` only when the task clearly creates or
changes direct-chat working-memory facts. Propose a unified diff targeting only
`memory/active.md` or `memory/followups.md`, with the target's current
`base_sha256` from the memory pack, then apply it through:

```bash
bash "$KNOT_ROOT/bin/knot-memory-apply.sh" apply \
  --root "$KNOT_ROOT" \
  --patch "$KNOT_ACTIVE_WORKSPACE/.knot/memory-patch.md" \
  --platform "$KNOT_PLATFORM" \
  --chat-id "$KNOT_CHAT_ID" \
  --user-id "$KNOT_PLATFORM_USER_ID" \
  --identity-key "$KNOT_IDENTITY_KEY" \
  --actor-user "$KNOT_ACTOR_USER" \
  --active-workspace "$KNOT_ACTIVE_WORKSPACE" \
  --user-workspace "$KNOT_USER_WORKSPACE" \
  --conversation-dir "$KNOT_CONVERSATION_DIR"
```

Do not edit memory files manually. Do not claim memory was updated unless this
helper succeeds.

For group chats, do not write group memory yet. Group memory is intentionally
blocked until group workspace routing and actor-shard patch validation are
implemented.
