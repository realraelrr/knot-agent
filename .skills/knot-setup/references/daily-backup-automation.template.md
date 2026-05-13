# Daily Backup Automation Template

Schedule: daily, once per day, local time.

Prompt:

```text
Run the daily Knot rollback backup for the current workspace.

Goal: commit and push durable rollback data once per day.

Use this scope when present:
- AGENTS.md
- .skills/knot-setup/
- .skills/knot-workflow/
- workspace/knowledge/
- workspace/admin/

Also support legacy Knot layouts by using these paths when workspace/ is absent:
- AGENTS.md
- .skills/knot-setup/
- .skills/knot-workflow/
- knowledge/

Never stage or commit runtime/, components/, logs, sockets, locks, local
secrets, caches, node_modules, or dependency checkouts. Do not commit IM runtime
credentials.

If the backup root is not a git repository, or remote `backup` is missing, do
not initialize git and do not add a remote. Report that backup setup is required
and include the missing condition.

Remote safety:
- Use only the customer-controlled remote named `backup`.
- Do not use `origin` or `scaffold` for durable data backup.
- If `git remote get-url backup` points to `realraelrr/knot-agent`, stop and
  report that the backup remote is unsafe.

If it is a git repository with a safe `backup` remote:
1. Check git status.
2. Stage only the durable backup scope using controlled `git add -f` for the
   allowlisted paths above.
3. Do not use broad `git add -A`.
4. If there are no staged changes, report that no backup commit was needed.
5. If there are staged changes, commit with message
   `chore: daily Knot rollback backup YYYY-MM-DD` using the current local date.
6. Push the current branch to remote `backup`.
7. Report the commit hash and pushed branch, or report the exact failure.
```
