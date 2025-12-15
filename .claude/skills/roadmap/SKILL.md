---
name: roadmap
description: Execute tasks from ROADMAP.md systematically. Use when the user asks to "complete roadmap tasks", "work on roadmap", "implement N tasks from roadmap", or references ROADMAP.md. Handles task selection, implementation, testing, and ROADMAP updates.
---

# Roadmap Task Executor

Complete tasks from ROADMAP.md systematically with proper implementation, testing, and documentation.

## Workflow

### 1. Read and Analyze ROADMAP.md

Read `ROADMAP.md` to identify uncompleted tasks (lines starting with `- [ ]`).

### 2. Select Tasks

Determine how many tasks to complete:
- If user specifies a number (e.g., "/roadmap 3"), select that many tasks
- If no number is specified, default to **1 task**

Select tasks starting from the first uncompleted one.

### 3. Implement Each Task

For each selected task:

**a) Understand Requirements**
- Analyze what the task requires
- Identify files that need modification
- If task description is unclear, use AskUserQuestion to clarify

**b) Implement Code**
- Make necessary code changes
- Follow project coding standards (see CLAUDE.md and ERRATA.md)
- Avoid over-engineering - only implement what's required

**c) Add Tests**
- Write tests in appropriate `*_test.mbt` files
- Use `compare_jit_interp()` for WASM execution tests
- Use `inspect()` for snapshot testing

**d) Verify Implementation**
```bash
moon test -p <package>  # Run affected tests
moon fmt                # Format code
moon info               # Update interface files
```

**e) Update ROADMAP.md**
- Change task from `- [ ]` to `- [x]`
- Update the "下一步" (Next Steps) section if needed

### 4. Handle Dependencies

If a task depends on unimplemented features:
- Skip the task
- Explain why it was skipped
- Move to the next task

### 5. Commit Changes

After completing all selected tasks:

```bash
moon fmt && moon info   # Prepare for commit
git add .
git commit -m "feat: <summary of completed tasks>"
```

### 6. Report Results

Provide a summary including:
- Which tasks were completed
- Files modified
- Lines of code added/changed
- Test results
- Any tasks skipped and why

## Best Practices

- Complete one task at a time thoroughly before moving to the next
- Update ROADMAP.md immediately after each task
- Don't lower code quality to complete more tasks
- Reference ERRATA.md for common mistakes to avoid
- Keep commits focused on the completed tasks

## Example Usage

```
User: /roadmap 2
```
This will complete the next 2 uncompleted tasks from ROADMAP.md.

```
User: /roadmap
```
This will complete the next 1 uncompleted task from ROADMAP.md.
