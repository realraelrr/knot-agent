# Component Sync

Knot uses pinned component repositories instead of vendoring all source into the
scaffold. `components.lock` is the reviewed component version list for the
installer, doctor, and release gate.

## Rules

- Update component repositories first, then update the root lockfile.
- Do not point `components.lock` at unreviewed local work.
- Do not mirror whole upstream repositories unless the component already owns
  that source boundary.
- Keep upstream skill licenses and notices intact.
- Run the component's own tests in the component repository when the component
  changes.

## General Component Update

1. Change the component under `components/<name>/`.
2. Run that component's relevant checks.
3. Commit and push the component repository.
4. Record the new component commit SHA.
5. Update the matching row in `components.lock`.
6. Run:

   ```bash
   bash bin/knot-doctor.sh --scaffold-only --strict-docs
   ```

7. Commit the root scaffold with the lockfile update.

## cc-connect

Use this when changing `components/cc-connect-local-main` or updating its pin.

```bash
cd components/cc-connect-local-main
GOMODCACHE=/private/tmp/knot-go-cache go test ./core ./cmd/cc-connect -count=1 -timeout=120s
git commit
git push origin main
git rev-parse HEAD
```

Then update the `cc-connect` row in `components.lock` and run the scaffold
doctor from the Knot root.

## Knot Skills

`components/knot-skills` is a curated skill distribution. It contains vendored
Office Pack skills and links first-party workbench skills from sibling
components.

When changing Knot-specific packaging:

1. Edit `components/knot-skills`.
2. Run the relevant packaging or lint checks available in that repository,
   including:

   ```bash
   bash tests/canary.sh
   ```

3. Commit and push `components/knot-skills`.
4. Update the `knot-skills` row in `components.lock`.
5. Run scaffold doctor from the Knot root.

## MiniMax Office Skills

Office Pack skills are sourced from `MiniMax-AI/skills`; Knot does not maintain
a full upstream mirror or a full Office golden-test suite.

When refreshing a MiniMax-sourced skill:

1. Copy only the selected upstream skill directory.
2. Preserve upstream license and notice files.
3. Keep the local Knot skill name stable unless a rename is explicitly part of
   the release.
4. Update `components/knot-skills/UPSTREAMS.md` with the upstream source
   commit.
5. Run the available Knot packaging checks and scaffold doctor.

Knot validates that the curated skill distribution installs and remains pinned.
Deep Office behavior quality stays with the upstream skill unless Knot makes a
substantive local change to that behavior.

## Release Blockers

- A component row in `components.lock` points to the wrong repository, path, or
  commit.
- The root scaffold doctor rejects the lockfile.
- A component change is not committed and pushed before the root lockfile points
  to it.
- A MiniMax-sourced refresh drops required license or upstream attribution.
