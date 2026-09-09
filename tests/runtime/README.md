# Runtime ownership regressions

Run the local cross-instance corpus in both engines:

```sh
python3 scripts/run_all_wast.py --dir tests/runtime --rec
```

`callable-context.wast` checks shared globals, callee GC context, cross-module
type identity, bounded native tail calls, precise caller roots during
callee allocation, and exception tags whose module-local indices differ.
The native test `callable_ownership_test.mbt` additionally checks executable
retention until Store retirement after explicit module closure.
