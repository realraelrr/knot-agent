---
name: knot-knowledge
description: Use when a Knot user wants shared organization knowledge added, corrected, or proposed for review.
---

# Knot Knowledge

Use this skill for durable organization knowledge changes. Do not use it for
ordinary Q&A, personal working style, single-task notes, or reusable workflow
steps.

## Route

- Stable enterprise facts, policies, SOPs, and source-backed decisions belong in
  the approved knowledge repo.
- User preferences and repeated corrections belong in `working-style`.
- Task progress and intermediate decisions belong in `planning-with-files`.
- Reusable procedures become workflow skill or SOP candidates.

## Proposal Flow

1. Distill the source into a small reviewable change. Keep raw conversions,
   sidecars, and scratch files in the active workspace.
2. Add or update a row in `workspace/admin/knowledge-feedback.md` with the
   source, proposed change, diff location, status, and execution notes.
3. Run `bin/knot-knowledge.sh propose` to create the local proposal bundle:

```bash
bash "$KNOT_ROOT/bin/knot-knowledge.sh" propose \
  --root "$KNOT_ROOT" \
  --source "$PROPOSAL_DIR" \
  --title "$SHORT_TITLE" \
  --platform "$KNOT_PLATFORM" \
  --user-id "$KNOT_PLATFORM_USER_ID" \
  --identity-key "$KNOT_IDENTITY_KEY" \
  --actor-user "$KNOT_ACTOR_USER"
```

4. Tell the user the knowledge proposal is ready for review. Do not claim the
   approved knowledge changed.

Only explicit `admin` users may approve durable knowledge. Members may propose;
operators do not automatically approve.

## Boundaries

Read approved knowledge from `workspace/knowledge/vault/` or a pinned approved
commit. Do not write directly to the approved mirror. Do not turn feedback into
fact without admin review, GitHub branch protection, and a visible diff.
