# HTTP resource contract verification

Date: 2026-09-30. Base: `905901f7`, with the authority setter fix in this working tree. Platform: macOS ARM64. The build is a fresh release build; `guests.json.gz` records its SHA-256, changed implementation hashes, upstream revision, guest checksums and full results.

The authority setter now validates URI syntax with the existing `marianoguerra/uri` parser. Userinfo, an empty authority and large numeric ports can be stored; actual HTTP transport still rejects unusable destinations before connecting. Invalid syntax still fails atomically. The new resource acceptance test failed before the implementation change. Existing path getter policy is retained, including distinct None, empty and slash values; no new normalization requirement is asserted.

All four checksum-verified, unchanged upstream HTTP command guests were executed with the new binary on both engines. Response and request-options pass (four executions). Fields and request fail (four executions) at the same original casing and empty-path assertions. No expectations were changed and no failure was hidden. Later assertions in those guests remain unreachable in these executions; source review is not a complete guest pass.

The double-engine HTTP integration runner passed, including mixed native timer/HTTP commands, streaming, trailers, disconnects and capability denial. Its output is retained in `http-integration.txt`. No new remote CI run is claimed by this report.

## Local validation

`moon info`, `moon fmt`, `moon check --target native --warn-list +73 --deny-warn` and all 2,632 native tests pass. The focused HTTP package passed 31 tests before the additional path round-trip assertions; the final full native run includes those assertions. Public generated interfaces are unchanged. Runtime production changes are limited to authority syntax validation.

## Upstream resolution

Filed [wasi-testsuite #291](https://github.com/WebAssembly/wasi-testsuite/issues/291), with exact guest/WIT revisions and observed values. It links existing [WASI #780](https://github.com/WebAssembly/WASI/issues/780) (optional path normalization), [#787](https://github.com/WebAssembly/WASI/issues/787) (mixed header casing), and [#949](https://github.com/WebAssembly/WASI/issues/949) (send-time empty paths). These are unresolved contract questions. The suite also accepts raw non-ASCII paths and bare percent signs and rejects empty authority; those expectations need explicit contract resolution. Local URI syntax must not be weakened solely to match one implementation's parser.

At this stage ISS-571 was left open pending upstream resolution. The subsequent user-authorized local test correction below supersedes that closure dependency; it does not claim upstream agreement.

## User-authorized test correction and final acceptance

The user authorized directly correcting the tests instead of waiting for upstream. The local [HTTP contract profile](../../../tests/wasi03/http-contract/README.md) retains a complete source patch, fixed Rust/Cargo dependencies, exact guest hashes, license and rebuild procedure. Both full guests execute to completion; later assertions were not removed to hide runtime bugs. They exposed missing Host and HTTP2-Settings restrictions, which were fixed in the runtime.

The final profile sweep reports **110 passes, zero failures**, across both engines. `contract-profile.json.gz` preserves its binary hash, override hashes, upstream revision, profile and individual results. The two replacement guests were rebuilt twice from committed upstream source plus the patch; both rebuilds match the checked-in bytes. The full native suite passes 2,633 tests; Python runner tests pass 178 tests with 54 platform-dependent skips. Warning-denied MoonBit checks, formatting and generated interfaces pass. Final both-engine HTTP integration output is in `http-integration-final.txt`.

CI now requests the explicit profile and fails on any non-pass result. The failure-acknowledgement mechanism has been removed. Running without the profile still selects unchanged upstream guests. This is local acceptance of the documented corrected suite, not a claim that the untouched upstream suite passes or that upstream has resolved #291. Remote CI for these changes has not been run.
