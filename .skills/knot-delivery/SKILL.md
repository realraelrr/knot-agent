---
name: knot-delivery
description: Use when a Knot user wants a generated or local file/image sent back through IM or chat.
---

# Knot Delivery

Use this skill when the user should receive a file or image in chat. Generation
is not delivery: a local path in the reply is not enough.

## Flow

1. Make sure the source file is in an allowed work location:
   - direct scope: current user's `work/`, `inbox/`, or `deliverables/`;
   - group scope: current group actor lane, excluding `.knot/` and `.state/`,
     or current group `deliverables/`.
2. Deliver it with `bin/knot-deliver.sh`:

```bash
bash "$KNOT_ROOT/bin/knot-deliver.sh" \
  --root "$KNOT_ROOT" \
  --kind file \
  --path "$ARTIFACT_PATH"
```

Use `--kind image` for images. The helper copies the source into the current
direct-user or authorized group `deliverables/` directory, validates the
outbound boundary, and prints the `cc-connect-attachments` block.

For a file already in the current deliverables directory, use
`bin/knot-attachment.sh` to validate and print the attachment block directly.

## Replies

Normal user-facing replies should be short and should not expose helper names,
local paths, audit details, or attachment-block syntax. Examples:

- `已生成并发送：report.pdf。`
- `已整理好文件并发送给你。`
- `已生成并发送 3 个文件：A.pdf、B.xlsx、C.md。`

Mention internal paths or commands only when the user asks for debugging or
implementation evidence.
