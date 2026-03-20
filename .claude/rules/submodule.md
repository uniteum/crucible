---
paths:
  - "solidity/**"
  - "solidity/README.md"
---

# Submodule Maintenance

- When updating the solidity README, verify all symlinks pointing into the submodule are documented in both the "What's in here" list and the "Adding to a repo" setup commands.
- When adding a new file to the submodule that consuming repos should symlink, update the README with the new symlink instruction.
- To find all symlinks: `find . -type l -exec readlink -f {} \;`
