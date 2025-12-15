---
name: auto-roadmap
description: Automatically execute all ROADMAP.md tasks with chained pull requests. Use when the user asks to "auto complete roadmap", "automatically implement roadmap", "create chained PRs for roadmap", or wants to execute all pending ROADMAP tasks at once. Creates a series of dependent PRs for systematic review.
---

# Auto Roadmap Executor

Continuously execute ROADMAP.md tasks and create chained pull requests for systematic review.

## Overview

This skill automates the complete ROADMAP execution by:
1. Implementing each task sequentially
2. Creating a feature branch for each task
3. Building a chain of dependent PRs
4. Allowing merge in sequential order

## Workflow

### Initialization

Record the current branch as the base branch (typically `main`).

### Main Loop

Continue until all tasks in ROADMAP.md are completed:

#### 1. Read Next Task

Find the first uncompleted task (`- [ ]`) in ROADMAP.md.

If no uncompleted tasks remain, proceed to final reporting and exit.

#### 2. Implement Task

**a) Analyze Requirements**
- Understand what the task requires
- Identify files to modify
- If unclear, use AskUserQuestion

**b) Code Implementation**
- Make necessary changes
- Follow ERRATA.md and CLAUDE.md guidelines
- Avoid over-engineering

**c) Add Tests**
- Write appropriate tests in `*_test.mbt` files
- Use `compare_jit_interp()` for WASM tests
- Use `inspect()` for snapshot tests

**d) Verify**
```bash
moon test -p <package>  # Unit tests
moon test               # All tests
moon fmt                # Format code
moon info               # Update interfaces
```

**e) Update ROADMAP.md**
- Mark task as completed: `- [ ]` → `- [x]`
- Update "下一步" (Next Steps) section

#### 3. Create Pull Request

**a) Prepare commit**
```bash
moon fmt && moon info
```

**b) Create feature branch**

For the first task:
```bash
git checkout -b feat/<task-description>
```

For subsequent tasks (branch from current):
```bash
git checkout -b feat/<next-task-description>
```

**c) Commit changes**
```bash
git add .
git commit -m "$(cat <<'EOF'
feat: <task summary>

<detailed description of implementation>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

**d) Push and create PR**

For the first task (base: main):
```bash
git push -u origin feat/<task-description>
gh pr create --base main --title "feat: <task summary>" --body "$(cat <<'EOF'
## Summary
<Implementation details>

## Changes
- <File changes>
- <Feature additions>

## Test Plan
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual verification

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

For subsequent tasks (base: previous branch):
```bash
git push -u origin feat/<next-task-description>
gh pr create --base feat/<previous-task> --title "feat: <task summary>" --body "$(cat <<'EOF'
## Summary
<Implementation details>

## Changes
- <File changes>
- <Feature additions>

## Dependencies
- Depends on PR #<previous-pr-number>

## Test Plan
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual verification

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

#### 4. Continue on Current Branch

Remain on the current feature branch and loop back to step 1 for the next task.

### Handling Blocked Tasks

If a task depends on unimplemented features:
- Skip the task
- Document why it was skipped
- Add a note in ROADMAP.md
- Continue with the next task

### Final Reporting

After all tasks are completed, provide:
- List of all created PRs with URLs
- Merge order (sequential from first to last)
- Summary of implementations
- Total lines changed
- Test coverage

## Branch Strategy

```
main
  └── feat/task-1 (PR #1 → main)
        └── feat/task-2 (PR #2 → feat/task-1)
              └── feat/task-3 (PR #3 → feat/task-2)
                    └── feat/task-4 (PR #4 → feat/task-3)
```

**Benefits:**
- Each PR shows only incremental changes
- PRs can be reviewed independently
- Merging in order incorporates all changes
- Easy to track progress

## Best Practices

- **Don't wait for user**: Continue to next task after creating PR
- **Quality over speed**: Don't lower code quality to complete more tasks
- **Test thoroughly**: Ensure each task works before moving on
- **Update ROADMAP**: Mark tasks complete immediately
- **Clear commit messages**: Explain what and why
- **Focused PRs**: One task per PR for easier review

## Important Notes

- Never use `commit --amend` or `push --force`
- Each PR builds on the previous branch
- Merge order matters - merge sequentially
- Keep ROADMAP.md updated in each commit
- Run tests before creating each PR

## Example Output

```
Task 1: Implement feature X
✓ Code implemented
✓ Tests added
✓ ROADMAP updated
✓ PR created: https://github.com/user/repo/pull/123

Task 2: Add feature Y
✓ Code implemented
✓ Tests added
✓ ROADMAP updated
✓ PR created: https://github.com/user/repo/pull/124 (depends on #123)

...

All tasks completed!
PRs created (merge in this order):
1. PR #123: Implement feature X
2. PR #124: Add feature Y
3. PR #125: Enhance feature Z

Total: 15 tasks completed, 1200 lines changed
```
