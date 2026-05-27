# Deployment Profiles

Knot is a thin local Codex harness. These profiles describe the deployment
posture that has been validated; they are not product tiers.

## Local Demo

Use for single-operator demos, scaffold validation, and internal development.

Required controls:

- `bash bin/knot-doctor.sh --scaffold-only --strict-docs`
- `bash bin/knot-permission-smoke.sh`
- local runtime secrets kept under `runtime/`
- no claim of OS, tenant, network, DLP, or platform-side isolation

Residual risk:

- all local files readable by the operating-system user remain readable by
  local processes;
- live IM identity mapping is not proven until platform smoke tests run.

## Internal Pilot

Use for small trusted teams running real IM workflows.

Required controls:

- all Local Demo checks;
- `bash bin/knot-doctor.sh --platform dingtalk,feishu,wecom,weixin` for the
  configured platforms;
- live IM smoke according to `docs/ops/im-smoke-sop.md`;
- a reviewed `workspace/admin/permissions.md`;
- a customer or operator secret vault for runtime credentials;
- centralized runtime logs or a defined log retention location.

Residual risk:

- Knot workspace routing is logical isolation, not OS isolation;
- members can propose knowledge changes, but only explicit admins approve and
  merge durable knowledge;
- platform-specific attachment/reference behavior must be validated per target
  platform.

## Enterprise Controlled

Use for high-risk enterprise environments where local process access, outgoing
network, and platform credentials must be governed outside Knot.

Required controls:

- all Internal Pilot controls;
- separate OS users, containers, VMs, or filesystem jails for high-risk tenant
  boundaries;
- enterprise secret vault injection with least-privilege runtime credentials;
- DLP/SIEM/EDR/MDM controls outside the Knot checkout;
- outbound network policy at the OS, proxy, or firewall layer;
- human approval gates for destructive actions and external sends;
- exported Knot audit events and platform delivery logs retained in the
  organization audit system.

Residual risk:

- Knot still does not classify all sensitive content in prompts, generated
  files, uploaded files, or logs;
- Codex session history remains the transcript source of truth and must be
  backed up and retained by the operator policy;
- platform readiness must be claimed only for tested platform/scenario pairs.

## Release Statement

Release notes should state the highest profile actually validated. Do not claim
Enterprise Controlled readiness unless external controls outside this repo are
configured and tested.
