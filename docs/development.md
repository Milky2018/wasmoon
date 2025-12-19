# Development Guide

Guide for developing and contributing to wasmoon.

## Prerequisites

- [MoonBit](https://www.moonbitlang.com/) toolchain
- Git
- Python 3 (for test scripts)
- lldb (for debugging)

## Setup

```bash
# Clone the repository
git clone https://github.com/user/wasmoon.git
cd wasmoon

# Set up git hooks
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks

# Build
moon build
./install.sh
```

## Development Commands

| Command | Description |
|---------|-------------|
| `moon check` | Type-check and lint |
| `moon test` | Run all tests |
| `moon fmt` | Format code |
| `moon info` | Update .mbti interface files |
| `moon build` | Build the project |

### Standard Workflow

```bash
# Before committing
moon info && moon fmt

# Run tests
moon test

# Build and install
moon build && ./install.sh
```

## Project Structure

```
wasmoon/
├── main/           # CLI entry point
├── wat/            # WAT parser
├── wast/           # WAST parser
├── cwasm/          # Binary parser
├── validator/      # Module validation
├── runtime/        # Runtime structures
├── executor/       # Interpreter
├── ir/             # SSA-based IR
├── vcode/          # VCode and register allocation
│   ├── abi/        # ABI definitions
│   ├── instr/      # VCode instructions
│   └── lower/      # IR to VCode lowering
├── jit/            # Machine code emission
├── wasi/           # WASI implementation
├── testsuite/      # Tests
└── docs/           # Documentation
```

## Testing

### MoonBit Tests

```bash
# Run all tests
moon test

# Run specific package tests
moon test -p testsuite -f i32_test.mbt

# Update snapshots (use sparingly)
moon test -p <package> -f <file> --update
```

### WAST Tests

```bash
# Run single WAST file
./wasmoon test spec/i32.wast

# Run all WAST tests
python3 scripts/run_all_wast.py

# Run without JIT
./wasmoon test --no-jit spec/i32.wast
```

### Writing Tests

Use `inspect` for snapshot testing:

```moonbit
test "my_test" {
  let result = my_function()
  inspect(result, content="expected output")
}
```

Use `compare_jit_interp()` for JIT regression tests:

```moonbit
test "jit_regression" {
  compare_jit_interp(
    #|(module
    #|(func (export "test") (result i32)
    #|  i32.const 42))
  )
}
```

## Debugging

### Using lldb

```bash
lldb -- ./wasmoon test path/to/test.wast
(lldb) run
(lldb) bt           # Stack trace
(lldb) frame info   # Current frame
(lldb) register read
```

### Exploring Compilation Stages

```bash
# View IR
./wasmoon explore test.wat --stage ir

# View machine code
./wasmoon explore test.wat --stage mc

# Compare JIT vs interpreter
./wasmoon test test.wast          # JIT mode
./wasmoon test --no-jit test.wast # Interpreter mode
```

## Code Style

### Block Style

MoonBit code is organized in blocks separated by `///|`:

```moonbit
///|
fn function_one() -> Unit {
  // ...
}

///|
fn function_two() -> Unit {
  // ...
}
```

### Naming Conventions

- Functions: `snake_case`
- Types: `PascalCase`
- Constants: `SCREAMING_SNAKE_CASE`
- Enum constructors: `PascalCase`

### Error Handling

```moonbit
// Define errors
type! MyError String

// Throw errors
fn may_fail() -> Int raise MyError {
  raise MyError("something went wrong")
}

// Handle errors
try { may_fail() } catch { MyError(msg) => println(msg) }

// Ignore errors
try! may_fail() |> ignore
```

## Git Workflow

1. Create a feature branch: `git checkout -b feat/my-feature`
2. Make changes and test
3. Format and update interfaces: `moon info && moon fmt`
4. Commit with conventional message: `feat: add new feature`
5. Push and create PR

### Commit Message Format

```
<type>: <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

## Adding New Instructions

1. Add instruction to `ir/inst.mbt`
2. Add lowering in `vcode/lower/lower.mbt`
3. Add machine code emission in `vcode/lower/codegen.mbt`
4. Add interpreter support in `executor/`
5. Add tests in `testsuite/`

## Common Issues

### Exit Code 134

Usually indicates a crash. Debug with lldb:
```bash
lldb -- ./wasmoon test failing_test.wast
```

### Snapshot Mismatch

Don't blindly update snapshots. Investigate the cause:
```bash
moon test -p <package> -f <file>
# Check the diff, understand the change
# Only then update if correct:
moon test -p <package> -f <file> --update
```

### Register Allocation Failures

Check that all virtual registers have proper definitions and uses. Enable VCode dumping:
```bash
./wasmoon explore test.wat --stage vcode
```
