---
paths:
  - "lib/**"
---

# Submodule Maintenance

## Branch rule

Everything under `lib/` is a git submodule with its own repo.
**Before committing any change inside any `lib/` subdirectory:**

1. `cd` into the submodule directory.
2. Run `git checkout main` — never commit on a detached HEAD.
3. Make the change and commit on `main`.
4. `cd` back to the parent repo and stage the updated submodule pointer.

This keeps each submodule's history linear on `main` and avoids orphaned
commits that require cherry-picks to recover.

## Other guidelines (crucible)

- When updating the crucible README, verify all symlinks pointing into the submodule are documented in both the "What's in here" list and the "Adding to a repo" setup commands.
- When adding a new file to the submodule that consuming repos should symlink, update the README with the new symlink instruction.
- To find all symlinks: `find . -type l -exec readlink -f {} \;`
