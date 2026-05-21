#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT_DIR=""

usage() {
  cat <<'EOF'
Usage: bash bootstrap/knot-im-smoke-plan.sh [--root DIR] [--out DIR]

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

Follow `docs/im-smoke-sop.md`.

## Release Gate

- Scaffold CI on current candidate commit passed.
- `bash bootstrap/doctor.sh --platform dingtalk,feishu,wecom,weixin` has been
  reviewed for local runtime readiness.
- All required rows in `results.tsv` are `pass`.
- Every `blocked` or `skipped` row has a reason.

## Human Execution Notes

- Use dedicated test users and test groups.
- Do not send secrets, production customer data, or private workspace files.
- Confirm generated images/files are actually received in the IM client.
- Save screenshots or copied request/response text under `evidence/` when useful.
EOF

cat > "$OUT_DIR/results.tsv" <<'EOF'
id	required	platform	chat_type	content_type	send_mode	permission_state	prompt	expected_result	operator	platform_user_id	chat_id	status	actual_result	evidence
smoke-001	yes	dingtalk	direct	long_text	direct	authorized	请用三句话总结 Knot 当前用途。	Text reply reaches the requester and no file attachment is sent.					
smoke-002	yes	dingtalk	group	image	direct	authorized	生成一张简单测试图片并发送到当前群。	Image attachment is delivered from the authorized group or actor deliverables boundary.					
smoke-003	yes	dingtalk	group	file	reply	authorized	引用上一条消息，生成一个测试 txt 文件并发送。	File attachment is delivered and reference metadata is preserved.					
smoke-004	yes	dingtalk	group	file	direct	unauthorized	尝试发送另一个用户或未授权群的文件。	Request is rejected without exposing another workspace.					
smoke-005	yes	feishu	direct	file	direct	authorized	生成一个测试 Markdown 文件并发送给我。	File attachment is delivered from the actor user deliverables boundary.					
smoke-006	yes	feishu	group	long_text	direct	authorized	在群里用长文说明 Knot 的 workspace 边界。	Text reply resolves actor user and current group.					
smoke-007	yes	feishu	group	image	reply	authorized	引用上一条消息，生成一张测试图片并发送。	Image attachment is delivered and reference metadata is preserved.					
smoke-008	yes	feishu	group	long_text	direct	unauthorized	尝试修改知识库或权限表。	Request is rejected with a clear authorization response.					
smoke-009	yes	wecom	direct	image	direct	authorized	生成一张简单测试图片并发送给我。	Image attachment is delivered from the actor user deliverables boundary.					
smoke-010	yes	wecom	group	file	direct	authorized	生成一个测试文件并发送到当前群。	File attachment is delivered from the authorized group or actor deliverables boundary.					
smoke-011	yes	wecom	group	long_text	reply	authorized	引用上一条消息，回复一段长文。	Text reply preserves reference metadata.					
smoke-012	yes	wecom	group	file	direct	unauthorized	尝试发送另一个用户或未授权群的文件。	Request is rejected without exposing another workspace.					
smoke-013	yes	weixin	direct	file	direct	authorized	生成一个测试 txt 文件并发送给我。	File attachment is delivered from the actor user deliverables boundary.					
smoke-014	yes	weixin	group	long_text	direct	authorized	在群里用长文说明 Knot 的交付边界。	Text reply resolves actor user and current group.					
smoke-015	yes	weixin	group	image	reply	authorized	引用上一条消息，生成一张测试图片并发送。	Image attachment is delivered and reference metadata is preserved.					
smoke-016	yes	weixin	group	long_text	direct	unauthorized	尝试修改知识库或权限表。	Request is rejected with a clear authorization response.					
EOF

printf 'Created IM smoke plan: %s\n' "$OUT_DIR"
printf 'Plan: %s\n' "$OUT_DIR/plan.md"
printf 'Results: %s\n' "$OUT_DIR/results.tsv"
