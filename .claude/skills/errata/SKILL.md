---
name: errata
description: Process TODO items from ERRATA.md and update the knowledge base with coding best practices. Use when the user asks to "work on errata", "complete errata todos", "update errata", or references ERRATA.md TODO items. Handles task execution, knowledge documentation, and ERRATA.md updates.
---

# Errata TODO Processor

Process TODO items from ERRATA.md by completing tasks and documenting learned best practices.

## Workflow

### 1. Read ERRATA.md

Locate the `## 待补充` (To Be Completed) section and identify all TODO items (lines starting with `- [ ]`).

### 2. Process Each TODO Item

For each TODO item, follow these steps:

**a) Understand the Task**
- Analyze what the TODO item requires
- Determine if it's a code improvement, test addition, or knowledge documentation task

**b) Execute the Task**

**For code improvements:**
- Locate relevant code files
- Make necessary changes following best practices
- Add tests if needed
- Run `moon test` to verify changes

**For knowledge documentation:**
- Research the topic if needed
- Prepare well-structured documentation
- Determine the appropriate section in ERRATA.md

**c) Update ERRATA.md**

Add learned knowledge to the appropriate section:
- MoonBit 编码规范 (MoonBit Coding Standards)
- WebAssembly 实现 (WebAssembly Implementation)
- 项目规范 (Project Standards)
- Other relevant sections

Update the TODO item:
- Change from `- [ ]` to `- [x]` if keeping it for reference
- Or delete the item entirely if no longer relevant

**d) Verify Changes**

Run tests to ensure changes don't break existing functionality:
```bash
moon test -p <package>  # For affected packages
moon test               # All tests
```

### 3. Use AskUserQuestion When Needed

If a TODO item requires clarification or decisions:
- Use AskUserQuestion to get user input
- Present clear options when applicable
- Document the decision in ERRATA.md

### 4. Maintain Format Consistency

When adding new knowledge to ERRATA.md:
- Follow existing formatting style
- Use appropriate headers and sections
- Include code examples where helpful
- Keep explanations concise and clear

**Example format:**
```markdown
### Topic Name

**错误写法** (Wrong way):
```moonbit
// Incorrect code example
```

**正确写法** (Correct way):
```moonbit
// Correct code example
```

Explanation of why the correct way is better.
```

### 5. Report Completion

After processing TODO items, provide a summary:
- Which TODO items were completed
- Code changes made (files, lines changed)
- New knowledge added to ERRATA.md
- Test results

## Best Practices

- Process one TODO item at a time thoroughly
- Update ERRATA.md immediately after completing each item
- Keep documentation concise and practical
- Include code examples for clarity
- Categorize knowledge into appropriate sections
- Run tests after code changes
- Ask for clarification rather than making assumptions

## Example Workflow

```
User: /errata
```
This will:
1. Read all TODO items from ERRATA.md
2. Process each item systematically
3. Update ERRATA.md with new knowledge
4. Mark completed items
5. Report what was done

## ERRATA.md Structure

The file typically contains these sections:
- **数组清空** (Array clearing)
- **错误处理** (Error handling)
- **忽略返回值** (Ignoring return values)
- **布尔取反** (Boolean negation)
- **函数调用** (Function calls)
- **循环** (Loops)
- **if-is 模式匹配** (if-is pattern matching)
- **可见性控制** (Visibility control)
- **类型转换** (Type conversion)
- **无符号运算** (Unsigned operations)
- **依赖管理** (Dependency management)
- **Git 规范** (Git conventions)
- **String 字符访问** (String character access)
- **构建和运行** (Build and run)
- **调试** (Debugging)
- **测试** (Testing)

Add new sections as needed when documenting new types of knowledge.
