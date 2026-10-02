# HTTP contract test profile

This directory contains two **modified upstream guests**, not an unmodified
upstream conformance result. Base: wasi-testsuite
`609c446139956ff30239f87cb18af1dc6128bed2`. `expectations.patch` is the complete
source diff. The other 53 guests remain byte-exact upstream artifacts.

The local policy follows the vendored `wasi:http@0.3.0` WIT and RFC 3986 URI
syntax. Unresolved upstream choices remain tracked in
[wasi-testsuite #291](https://github.com/WebAssembly/wasi-testsuite/issues/291),
[WASI #780](https://github.com/WebAssembly/WASI/issues/780) and
[WASI #787](https://github.com/WebAssembly/WASI/issues/787).

| Correction | Basis and coverage |
| --- | --- |
| Preserve each appended field name's casing | `fields.copy-all` WIT explicitly specifies original casing. Case-insensitive lookup tests remain. |
| Preserve the empty path in the getter | Explicit lossless accessor policy while upstream #780 discusses optional normalization. Sending an empty path still produces `/`. |
| Validate URI characters and percent encodings | RFC 3986 sections 2.1 and 3.3: bare `%` and raw non-ASCII are not valid URI syntax. Add valid and invalid percent-encoding cases. Remove the old exemptions for invalid path characters. |
| Permit empty authority, userinfo and numeric ports outside u16 | RFC 3986 section 3.2 syntax is distinct from HTTP transport policy. Actual sends still reject unusable destinations. |
| Restore authority character iteration | The original `ch != '['` condition skipped virtually the whole loop. Exercise all 1,024 code points and add IPv6 and malformed percent encodings. |

The original forbidden-header assertions are preserved. Reaching them exposed
missing `http2-settings` and `host` rejection in Wasmoon; the runtime was fixed
rather than removing those assertions. These fields are controlled by the
transport, alongside connection and upgrade headers. Other pre-existing guest
exemptions unrelated to this change remain visible in the upstream source.

## Running

```sh
python scripts/run_wasi03.py --upstream /path/to/wasi-testsuite \
  --wasmoon ./wasmoon --output /tmp/wasi03-contract --http-contract-tests
```

CI uses this explicit profile and requires every test to pass. Omit
`--http-contract-tests` for the untouched upstream suite. That strict original
mode still reports the original casing/path mismatches as failures. There is no
failure acknowledgement or unexpected-pass exception. Each result records its
guest source, and the summary records the profile and replacement hashes. The
original corpus is checksum-verified even when the profile is selected.

## Rebuilding

Prerequisites: Python, Git, Rust 1.97.0 with the `wasm32-wasip2` target. The Rust
target matches upstream's core compilation target; the generated bindings still
use the pinned Preview 3 WIT. Cargo's dependency versions are locked. Only the
CLI/HTTP library modules needed by these two guests are compiled.

```sh
rustup target add --toolchain 1.97.0 wasm32-wasip2
python tests/wasi03/http-contract/rebuild.py \
  --upstream /path/to/wasi-testsuite --output /tmp/http-contract-rebuilt
```

The script reads committed source and WIT from the pinned Git revision, applies
the patch in a temporary directory, and builds with `cargo --locked`. It does
not alter the upstream checkout or silently replace checked-in binaries. Compare
output hashes with `manifest.json`; intentionally updated binaries and their
hashes must be reviewed together. Repeated local rebuilds are checked for byte
identity. The checked-in binaries let normal CI run without a Rust build.

Upstream source and derived binaries are covered by the accompanying Apache-2.0
LICENSE. Build metadata and local corrections are retained alongside them.
