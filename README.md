# Knot Agent

Public scaffold for a local Knot Codex agent workspace.

[中文 README](README.zh-CN.md)

Knot Agent is a local-first runtime scaffold for enterprise digital workers. It
gives a Codex-powered agent the workspace, knowledge layout, permission
contract, IM routing, deliverable boundaries, runtime checks, and setup flow it
needs to operate as a durable business role across users and channels.

This repository is the thin starting point for Codex. It contains the operating
guide, setup skills, runtime checks, and workspace layout rules. Component
repositories, runtime credentials, logs, customer data, and working files stay
local and are not part of this scaffold.

## Start Here

1. Open Codex from the Knot root.
2. Read `AGENTS.md`; it is the workspace operating guide.
3. Use the `knot-setup` skill to install or repair the workspace.
4. After setup, use `knot-workflow` to route knowledge, IM, attachment, and
   deliverable tasks.

## Boundaries

- Source repos live under `components/`.
- User files, drafts, deliverables, and task state live under `workspace/`.
- Runtime configs, logs, sockets, and local secrets live under `runtime/`.
- Do not put generated work in the repository root.

Licensed under the Apache License 2.0. See `LICENSE`.
