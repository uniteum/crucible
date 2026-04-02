---
paths:
  - "lib/crucible/**"
  - "lib/crucible/README.md"
---

# Submodule Maintenance

## Branch rule

Crucible is consumed as a git submodule by other repos.
**Before committing any change inside `lib/crucible/`:**

1. `cd` into the submodule directory.
2. Run `git checkout main` — never commit on a detached HEAD.
3. Make the change and commit on `main`.
4. `cd` back to the parent repo and stage the updated submodule pointer.

This keeps crucible's history linear on `main` and avoids orphaned
commits that require cherry-picks to recover.

## Other guidelines

- When updating the crucible README, verify all symlinks pointing into the submodule are documented in both the "What's in here" list and the "Adding to a repo" setup commands.
- When adding a new file to the submodule that consuming repos should symlink, update the README with the new symlink instruction.
- To find all symlinks: `find . -type l -exec readlink -f {} \;`
