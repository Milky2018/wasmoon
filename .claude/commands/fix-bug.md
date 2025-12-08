# Fix Bug Command

Fix the bug or issue specified by the user argument.

## Input
$ARGUMENTS

## Workflow

1. **Reproduce the bug**: Run the provided command or test to understand the failure
2. **Analyze the error**: Identify the root cause by examining error messages and relevant code
3. **Create a regression test**: If no test exists for this bug, write a unit test in the appropriate `*_test.mbt` file that reproduces the issue
4. **Fix the bug**: Modify the code to fix the issue
5. **Verify the fix**: Run the test to confirm the fix works, and ensure no regressions in related tests
6. **Commit and create PR**:
   - Create a new branch with format `fix/<descriptive-name>`
   - Commit with a clear message explaining the fix
   - Push and create a PR with summary and test plan

## Notes
- Always create a test first if one doesn't exist
- Run `moon test -p <package>` to verify unit tests
- Run `moon build && ./install.sh` before running `./wasmoon` commands
- Follow the project's commit message conventions
