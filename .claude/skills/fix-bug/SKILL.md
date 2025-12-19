---
name: fix-bug
description: Systematic bug fixing workflow with regression tests and PR creation. Use when the user asks to "fix a bug", "debug an issue", "resolve a problem", or provides error messages/failing tests to fix. Handles reproduction, root cause analysis, test creation, fix implementation, and PR submission.
---

# Fix Bug Workflow

1. **Reproduce**: Run the failing test to observe the error
2. **Analyze**: Locate root cause using Grep/Read, explore with `./wasmoon explore`
3. **Write regression test first**: Create test in `testsuite/` that fails
4. **Fix**: Make minimal focused changes
5. **Verify**: `moon test` (all tests pass)
6. **Commit**: Create `fix/<name>` branch, commit with root cause explanation
7. **PR**: Only if requested - `git push && gh pr create`
