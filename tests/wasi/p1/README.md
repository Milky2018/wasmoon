# WASI Preview 1 regressions

Run the curated CLI smoke suite from the repository root:

```sh
python3 tests/wasi/p1/wasi_test.py
```

The same 45 cases run through both JIT and interpreter modes, checking their
original output, exit status and failure diagnostics. The runner creates and
removes its filesystem fixtures in a temporary directory.

The independent WAST regressions, formerly under `myspec/wasip1/`, use the
existing Core WAST runner:

```sh
python3 scripts/run_all_wast.py --dir tests/wasi/p1 --rec
```

The `.wat` inputs and `fixtures/` are not discovered as WAST trials. The two
auxiliary fixtures retain their manual CLI entry points:

```sh
./wasmoon run tests/wasi/p1/fixtures/wasi_file_test.wat
./wasmoon run tests/wasi/p1/fixtures/wasi_invalid_rights.wat --dir .
```
