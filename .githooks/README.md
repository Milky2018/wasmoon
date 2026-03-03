# Git Hooks

## Pre-commit Hook

This pre-commit hook performs automatic checks before finalizing your commit.
It runs:

- `moon fmt`
- `moon info`
- `moon check --target native`

If `moon fmt` or `moon info` changes tracked files, the commit is stopped so you
can review and stage the updates first.

### Usage Instructions

To use this pre-commit hook:

1. Make the hook executable if it isn't already:
   ```bash
   chmod +x .githooks/pre-commit
   ```

2. Configure Git to use the hooks in the .githooks directory:
   ```bash
   git config core.hooksPath .githooks
   ```

3. The hook will automatically run when you execute `git commit`
