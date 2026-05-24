# Release Gate

This is the single entry point for Knot release validation. It explains which
existing gate to run and when. It does not replace `doctor.sh`, CI,
`components.lock`, or the IM smoke SOP.

## Gate Layers

| Gate | Command or source | Mode | Required when | Pass signal |
|---|---|---|---|---|
| Scaffold CI | `.github/workflows/scaffold-ci.yml` | Automatic | Every PR and push to `main` | All workflow steps pass |
| Scaffold source | `bash bootstrap/doctor.sh --scaffold-only --strict-docs` | Local/CI | Scaffold, docs, installer, helper, or lockfile changes | No `MISS` or failed smoke checks |
| Installed runtime | `bash bootstrap/doctor.sh` | Local | Before tagging or validating an installed workspace | No `MISS`; advisory warnings are reviewed |
| Platform runtime | `bash bootstrap/doctor.sh --platform dingtalk,feishu,wecom,weixin` | Local | Before live IM smoke for configured platforms | No missing runtime files for target platforms |
| Permission smoke | `bash bootstrap/knot-permission-smoke.sh` | Local/doctor | Before release and before live IM smoke | All permission checks print `OK` |
| Component pins | `components.lock`, validated by installer and doctor | Local/CI | Any component revision change | Pinned refs match reviewed component commits |
| cc-connect core | `GOMODCACHE=/private/tmp/knot-go-cache go test ./core -count=1 -timeout=120s` from `components/cc-connect-local-main` | Component local/CI | Any cc-connect change or cc-connect pin update | Go tests pass |
| Live IM smoke | `docs/im-smoke-sop.md` and `bash bootstrap/knot-im-smoke-plan.sh` | Manual | Final release validation for IM behavior | Required rows pass; skipped or blocked rows have explicit reasons |

## CI Alignment

Scaffold CI is intentionally the automated source gate. It runs shell syntax,
shellcheck, and `bash bootstrap/doctor.sh --scaffold-only --strict-docs`.

It does not claim installed runtime readiness, live IM readiness, or complete
component-internal validation. Those stay in the installed doctor, platform
doctor, IM smoke SOP, and component repositories.

## Release Sequences

For scaffold-only changes:

```bash
bash -n bootstrap/*.sh bootstrap/doctor/*.sh tests/*.sh
shellcheck --severity=warning -x bootstrap/*.sh bootstrap/doctor/*.sh tests/*.sh
bash bootstrap/doctor.sh --scaffold-only --strict-docs
```

For installed runtime validation:

```bash
bash bootstrap/doctor.sh
```

For permission or delivery boundary changes:

```bash
bash bootstrap/knot-permission-smoke.sh
bash bootstrap/doctor.sh --scaffold-only --strict-docs
```

For cc-connect changes:

```bash
cd components/cc-connect-local-main
GOMODCACHE=/private/tmp/knot-go-cache go test ./core -count=1 -timeout=120s
```

For final IM release validation:

```bash
bash bootstrap/doctor.sh --platform dingtalk,feishu,wecom,weixin
bash bootstrap/knot-im-smoke-plan.sh
```

Then execute the generated IM smoke plan according to `docs/im-smoke-sop.md`.

For component updates, follow `docs/component-sync.md`.

For customer or pilot deployments, collect the required runtime boundary inputs
from `docs/deployment-inputs.md`.

## Release Blockers

- Scaffold CI fails.
- `doctor.sh` reports a hard failure.
- `knot-permission-smoke.sh` fails.
- A component pin does not match the reviewed component commit.
- A target IM platform cannot start its configured runtime.
- Live IM smoke fails attachment delivery, identity routing, reply/reference
  handling, or permission-boundary checks.
- Local secrets, runtime logs, conversation metadata, or another user's
  workspace files are sent or exposed as deliverables.

## Advisory Warnings

Advisory warnings do not automatically block a scaffold release, but they must
be reviewed before a final release.

- `no platform checks requested` is acceptable only when the current validation
  does not claim live platform readiness.
- A blocked live IM row is acceptable only when the release notes explicitly
  state the coverage gap and the target release does not claim that platform or
  scenario as fully validated.

## Boundaries

Do not add a wrapper release script unless repeated manual execution becomes a
real source of mistakes. Keep deterministic checks in `doctor.sh` and
permission smoke, keep live-platform behavior in the IM smoke SOP, and keep
component-internal tests in their component repositories.
