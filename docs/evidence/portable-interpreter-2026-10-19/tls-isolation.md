# TLS fixture isolation

ISS-643 addresses the downstream test interaction described in the
[timing diagnosis](http-timing-diagnosis.md). The async library's synchronous
Windows PFX import is reported separately as
[moonbitlang/async#669](https://github.com/moonbitlang/async/issues/669).
This change does not modify that library or claim to repair its blocking path.

The HTTPS trust test now uses the public HTTP/component interfaces from the
blackbox executable. HTTP timer tests remain in the whitebox executable, so
their coroutines no longer share the TLS server's event-loop thread. No
production API was exposed for testing. Both custom-root acceptance and
untrusted-certificate rejection remain covered, and the peer consumes the
complete empty chunked request before responding.

All 32 HTTP tests are retained. The TLS outer deadline remains 10000ms; HTTP
deadline tests are unchanged. The fixture bounds its complete request exchange
by the existing 3000ms read budget rather than extending any deadline.

## Controlled regression

`WASMOON_TEST_BLOCKING_TLS_SETUP=1` makes the test deliberately occupy its
thread for 3200ms before the first TLS setup. It does not change any deadline.
The default test run has no injected delay. CI also runs the controlled mode
on every native platform with serialized test-executable execution.

The counterfactual temporarily moved this same public-API test back into the
whitebox executable, adjusting only its self-import and test-import placement.
With the control enabled, the three-test cohort reproduces the original
backpressure `TimeoutError` and empty-body failure; TLS verification passes.
Restoring the isolated layout passes all 32 tests in both parallel and
serialized executable modes with the same control enabled. This checks the
observable interference rather than relying only on a filename assertion.

All native CI workspace gates now serialize executable execution with
`--no-parallelize`. Linux and the Windows inventory runner already did so;
the follow-up removes the macOS exception. Async tasks inside one executable
remain concurrent, which is why the TLS fixture still requires isolation.

[Local receipt](tls-isolation-local.json) records the actual source hashes,
dirty precommit provenance, the counterfactual mutation and the unchanged
source used for the passing controls. These macOS controls are not Windows CI
acceptance. Ordinary native tests pass 2786/2786; info/fmt, strict native
checking and the package-boundary audit pass. These local results retain their
original provenance.
The local receipt predates the CI serialization follow-up and retains the
workflow hash for the isolation change before that separate scheduling change.

## Clean CI acceptance

All six jobs passed for repair head `357aee62` in
[run 39272603678](https://github.com/Milky2018/wasmoon/actions/runs/39272603678).
The [separate CI receipt](tls-isolation-ci.json) verifies the forced-blocking
32/32 gate on all four native platforms, both Windows inventories at
2786 tests / 60 packages, strict C 43, HTTP contract 110, misc 692 plus 72
script-only runs, actual MASM probes and packaged wasm embedding. Linux
sanitizer passed 193/193 with LSan enabled and all detection controls; native
and actual wasm each passed 258 Core files / 62563 assertions. Both artifacts
have clean source merge `c8d5c41d` with the expected main and repair parents.

ISS-643 is closed with this downstream acceptance. The final documentation
head requires a separate six-job CI run. Upstream async #669 remains open,
and PR #545 remains unmerged during review.
