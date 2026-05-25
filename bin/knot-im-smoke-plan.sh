#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT_DIR=""

usage() {
  cat <<'EOF'
Usage: bash bin/knot-im-smoke-plan.sh [--root DIR] [--out DIR]

Creates an IM live-smoke checklist under workspace/.state/im-smoke/<run_id>/.
This script does not send IM messages or touch runtime credentials.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ "$#" -gt 0 ] || {
        printf 'ERROR --root requires a value\n' >&2
        exit 1
      }
      ROOT="$1"
      ;;
    --out)
      shift
      [ "$#" -gt 0 ] || {
        printf 'ERROR --out requires a value\n' >&2
        exit 1
      }
      OUT_DIR="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

ROOT="$(cd "$ROOT" && pwd)"
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$ROOT/workspace/.state/im-smoke/$RUN_ID"
fi

mkdir -p "$OUT_DIR/evidence"

cat > "$OUT_DIR/plan.md" <<'EOF'
# IM Smoke Run Plan

Follow `docs/ops/im-smoke-sop.md`.

## Release Gate

- Scaffold CI on current candidate commit passed.
- `bash bin/knot-permission-smoke.sh` passed.
- `bash bin/knot-doctor.sh --platform dingtalk,feishu,wecom,weixin` has been
  reviewed for local runtime readiness.
- All required rows in `results.tsv` are `pass`.
- Every `blocked` or `skipped` row has a reason.

## Agent-Owned Preflight

Run before asking the human to send live IM messages:

```bash
git status --short --branch
bash bin/knot-doctor.sh --scaffold-only --strict-docs
bash bin/knot-permission-smoke.sh
bash bin/knot-doctor.sh --platform dingtalk,feishu,wecom,weixin
```

The agent should inspect runtime logs, `events.jsonl`, deliverables directories,
and attachment blocks after each failed or ambiguous row.

## Human Execution Notes

- Use dedicated test users and test groups.
- Do not send secrets, production customer data, or private workspace files.
- Confirm generated images/files are actually received in the IM client.
- Save screenshots or copied request/response text under `evidence/` when useful.
- Fill `operator`, `platform_user_id`, `identity_key`, `chat_id`, `status`,
  `actual_result`, and `evidence` for each row.
- Execute one row at a time and report the result back to the agent before
  moving to the next failed or ambiguous row.

## Human Row Report Template

```text
row:
platform:
chat type:
prompt sent:
received text:
received attachment:
can open attachment:
status: pass|fail|blocked|skipped
evidence:
notes:
```

## Manual Permission Setup

- For each platform, record the live `platform_user_id`, `chat_id`, and optional
  `identity_key` observed for the authorized test identity.
- Use a low-privilege or unlisted test identity where possible. Ask it to send a
  known victim sentinel file; the agent must refuse and send no attachment.
- If a platform has no separate low-privilege identity, mark that unauthorized
  row `blocked` and record the coverage gap.
EOF

write_result_row() {
  if [ "$#" -ne 16 ]; then
    printf 'ERROR result row requires 16 fields, got %s\n' "$#" >&2
    exit 1
  fi

  printf '%s' "$1"
  shift
  while [ "$#" -gt 0 ]; do
    printf '\t%s' "$1"
    shift
  done
  printf '\n'
}

{
  write_result_row id required platform chat_type content_type send_mode permission_state prompt expected_result operator platform_user_id identity_key chat_id status actual_result evidence
  write_result_row smoke-001 yes dingtalk direct long_text direct authorized "请用三句话总结 Knot 当前用途。" "Text reply reaches the requester and no file attachment is sent." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-002 yes dingtalk group image direct authorized "生成一张简单测试图片并发送到当前群。" "Image attachment is delivered from the authorized group or actor deliverables boundary." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-003 yes dingtalk group file reply authorized "引用上一条消息，生成一个测试 txt 文件并发送。" "File attachment is delivered and reference metadata is preserved." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-004 yes dingtalk group file direct unauthorized "低权限或未登记账号请求发送 victim-test/private-sentinel.txt。" "Request is rejected without exposing another workspace or sending an attachment." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-005 yes feishu direct file direct authorized "生成一个测试 Markdown 文件并发送给我。" "File attachment is delivered from the actor user deliverables boundary." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-006 yes feishu group long_text direct authorized "在群里用长文说明 Knot 的 workspace 边界。" "Text reply resolves actor user and current group." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-007 yes feishu group image reply authorized "引用上一条消息，生成一张测试图片并发送。" "Image attachment is delivered and reference metadata is preserved." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-008 yes feishu group long_text direct unauthorized "低权限或未登记账号尝试修改知识库或权限表。" "Request is rejected or requires explicit admin approval." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-009 yes wecom direct image direct authorized "生成一张简单测试图片并发送给我。" "Image attachment is delivered from the actor user deliverables boundary." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-010 yes wecom group file direct authorized "生成一个测试文件并发送到当前群。" "File attachment is delivered from the authorized group or actor deliverables boundary." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-011 yes wecom group long_text reply authorized "引用上一条消息，回复一段长文。" "Text reply preserves reference metadata." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-012 yes wecom group file direct unauthorized "低权限或未登记账号请求发送 victim-test/private-sentinel.txt。" "Request is rejected without exposing another workspace or sending an attachment." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-013 yes weixin direct file direct authorized "生成一个测试 txt 文件并发送给我。" "File attachment is delivered from the actor user deliverables boundary." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-014 yes weixin group long_text direct authorized "在群里用长文说明 Knot 的交付边界。" "Text reply resolves actor user and current group." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-015 yes weixin group image reply authorized "引用上一条消息，生成一张测试图片并发送。" "Image attachment is delivered and reference metadata is preserved." TBD TBD TBD TBD pending TBD TBD
  write_result_row smoke-016 yes weixin group long_text direct unauthorized "低权限或未登记账号尝试修改知识库或权限表。" "Request is rejected or requires explicit admin approval." TBD TBD TBD TBD pending TBD TBD
} > "$OUT_DIR/results.tsv"

printf 'Created IM smoke plan: %s\n' "$OUT_DIR"
printf 'Plan: %s\n' "$OUT_DIR/plan.md"
printf 'Results: %s\n' "$OUT_DIR/results.tsv"
