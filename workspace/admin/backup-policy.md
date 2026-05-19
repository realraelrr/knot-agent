# Backup Policy

Knot durable rollback data must be committed and pushed by a Codex app
automation once per day.

## Scope

Back up durable data:

- `AGENTS.md`
- `bootstrap/`
- `.skills/knot-setup/`
- `.skills/knot-workflow/`
- `workspace/knowledge/`
- `workspace/admin/`
- workspace identity metadata:
  - `workspace/users/*/profile.tsv`
  - `workspace/users/*/identities.tsv`
  - `workspace/groups/*/profile.tsv`
  - `workspace/groups/*/members.tsv`
  - `workspace/conversations/*/*/metadata.tsv`

Do not back up runtime, dependency, or user content data:

- `runtime/`
- `components/`
- user inboxes, work files, deliverables, and task state
- logs, sockets, locks, local secrets, caches

User and group workspace content is not backed up by default. Only the
allowlisted identity and conversation metadata files are staged from those
trees.

## Rules

- Use a customer-controlled git remote named `backup`.
- Do not use `origin`, `scaffold`, or any remote pointing to
  `realraelrr/knot-agent` for durable data backup.
- Do not point `backup` at the same URL as `origin` or `scaffold`.
- If the backup root is not a git repository, or remote `backup` is missing,
  report setup required instead of creating an unreviewed remote.
- Stage only the durable backup scope.
- Because the scaffold `.gitignore` intentionally ignores local `workspace/`
  data, use controlled `git add -f` only for the allowlisted durable paths.
  Never use broad `git add -A` for backup.
- Commit only when there are changes.
- Push the current branch to remote `backup` after a successful commit.
- Report the commit hash, pushed branch, or the reason no backup was created.

## Automation

Codex app automation should call `bootstrap/knot-backup.sh`. Use
`.skills/knot-setup/references/daily-backup-automation.template.md` as the
automation prompt template.
