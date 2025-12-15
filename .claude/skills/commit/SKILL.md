---
name: commit
description: Safe git commit workflow that prevents commits to main branch. Use when the user asks to "commit changes", "save changes", "git commit", or when completing a task that needs version control. Automatically creates feature branches when on main. NEVER creates pull requests unless explicitly requested by the user.
---

# Safe Commit Workflow

Commit changes safely by ensuring you never commit directly to the main branch.

## Core Rules

1. **NEVER commit to main branch**
2. **If on main**: Create a new feature branch first
3. **If on feature branch**: Commit directly
4. **NEVER create PRs** unless user explicitly asks

## Workflow

### 1. Check Current Branch

```bash
git branch --show-current
```

### 2. Branch Decision

**If current branch is `main`:**

Create a new feature branch based on the type of change:

```bash
# For new features
git checkout -b feat/<descriptive-name>

# For bug fixes
git checkout -b fix/<descriptive-name>

# For refactoring
git checkout -b refactor/<descriptive-name>

# For documentation
git checkout -b docs/<descriptive-name>
```

**Branch naming guidelines:**
- Use lowercase
- Use hyphens to separate words
- Be descriptive but concise
- Examples: `feat/bulk-operations`, `fix/multi-table-abi`, `refactor/remove-abi-v1-code`

**If current branch is NOT `main`:**

Proceed directly to commit.

### 3. Prepare Changes

```bash
moon fmt      # Format code
moon info     # Update interface files
git status    # Review changes
```

### 4. Commit Changes

Use conventional commit message format with HEREDOC:

```bash
git add .
git commit -m "$(cat <<'EOF'
<type>: <brief description>

<detailed description of what changed and why>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

**Commit types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `refactor:` - Code refactoring
- `docs:` - Documentation changes
- `test:` - Test additions or changes
- `chore:` - Build/tooling changes

### 5. Verify Commit

```bash
git log -1        # View the commit
git status        # Verify clean state
```

## Important Notes

### About Pull Requests

**DO NOT create pull requests automatically.** Only create a PR when the user explicitly asks with phrases like:
- "Create a PR"
- "Submit a pull request"
- "Open a PR"
- "Make a pull request"

If the user just asks to "commit" or "save changes", ONLY commit - do NOT create a PR.

### About Pushing

After committing:
- Inform the user the commit is complete
- Mention the branch name
- **Do NOT** automatically push unless requested
- **Do Not** automatically create PRs unless requested

The user will decide when to push and create PRs.

## Example Scenarios

### Scenario 1: User asks to commit (currently on main)

```bash
# Check branch
git branch --show-current  # Returns: main

# Create feature branch
git checkout -b feat/add-new-instruction

# Format and commit
moon fmt && moon info
git add .
git commit -m "$(cat <<'EOF'
feat: add support for new WASM instruction

Implement xyz instruction with proper lowering and code generation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"

# Inform user
# "Changes committed to branch feat/add-new-instruction"
```

### Scenario 2: User asks to commit (currently on feature branch)

```bash
# Check branch
git branch --show-current  # Returns: feat/bulk-operations

# Already on feature branch, commit directly
moon fmt && moon info
git add .
git commit -m "$(cat <<'EOF'
feat: implement memory.copy operation

Add memory.copy with tests and documentation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"

# Inform user
# "Changes committed to branch feat/bulk-operations"
```

### Scenario 3: User explicitly asks for PR

Only in this case, create a PR:

```bash
git push -u origin <branch-name>
gh pr create --title "<title>" --body "..."
```

## Commit Message Best Practices

1. **First line**: Type and brief summary (50 chars or less)
2. **Body**: Detailed explanation of what and why
3. **Focus on why**: Explain the reasoning, not just what changed
4. **Be specific**: "Add support for memory.copy" not "Add feature"
5. **Use imperative mood**: "Add" not "Added" or "Adds"

## Safety Checks

Before committing, verify:
- [ ] Tests pass (`moon test`)
- [ ] Code is formatted (`moon fmt`)
- [ ] Interfaces updated (`moon info`)
- [ ] Not on main branch
- [ ] Commit message is clear and descriptive
