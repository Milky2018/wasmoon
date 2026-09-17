# WASI HTTP serve functional audit

The initial HTTP CI runner started real Wasmoon CLI processes and sent TCP
requests, but it was a smoke/regression suite, not comprehensive HTTP
conformance evidence. The 2,522 native-test count covers the entire project.
It must not be presented as 2,522 HTTP service tests.

## Reproduced failures

All three wire failures reproduced independently on both engines using the
previous release executable. An empty component also demonstrated the startup
failure on the previous executable.

| Input | Before | Required regression |
| --- | --- | --- |
| `Expect: 100-Continue` | 417 | Receive 100 before sending the body, then 200 with the echoed bytes |
| Absolute URI request target | 400 | Deliver the URI path and authority to the guest, ignoring the Host value for routing |
| Chunk extensions | Invalid `;=` accepted; valid whitespace/quoted byte values not fully supported | Parse token/quoted-string extension syntax, accept BWS and obs-text, reject malformed extensions without a successful end marker |
| Empty component as service | Listen, then return 500 per request | Reject the missing HTTP handler export before binding |

The protocol requirements come from [RFC 9110 section 10.1.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.1.1), [RFC 9112 section 3.2.2](https://www.rfc-editor.org/rfc/rfc9112.html#section-3.2.2), and [RFC 9112 section 7.1.1](https://www.rfc-editor.org/rfc/rfc9112.html#section-7.1.1).

## Stronger executable evidence

`scripts/test_wasi_http.py` tests both engines through a fresh CLI process and
TCP for every server configuration. It covers:

- Expect case variants and combined values, with a client that waits for 100
  before uploading; absolute targets, HEAD, OPTIONS and custom methods.
- Valid/invalid chunk extensions, malformed length/transfer framing, and
  duplicate trailer names/casing.
- Incremental streaming: the second upload chunk is withheld until the first
  response chunk arrives. A whole-request buffering implementation times out.
- Empty, small and 2 MiB binary bodies; 16 requests over eight concurrent clients.
- 300 abandoned uploads per echo configuration, half after observing response
  headers, followed by a successful request. This exceeds the 256-slot server
  limit and detects unreclaimed connection slots in those paths.
- Two middleware components that modify the path. The service exposes its
  observed path/authority in response headers, making invocation order and
  target reconstruction externally observable.
- Outgoing proxy traffic under deny/loopback policies; repeated guest traps;
  missing-handler service/middleware startup rejection and occupied-port errors.

The echo and metadata guests also ran on independently downloaded Wasmtime
48.0.2 with Preview 3 enabled. An absolute-form POST returned status 200,
`oracle-body`, path `/independent?q=1` and authority `example.test`. This is
fixture interoperability evidence, not a complete Wasmtime differential sweep.
The fixtures are encoded and validated with wasm-tools 1.254.0.

## Reproduction

Build the intended executable first and pass it explicitly:

```sh
moon build --target native modules/wasmoon/cmd/wasmoon
python3 scripts/test_wasi_http.py --wasmoon target/native/debug/build/Milky2018/wasmoon/cmd/wasmoon/wasmoon.exe
moon check --target native --warn-list +73 --deny-warn
moon test --target native
```

The same runner remains enabled in the four-platform CI workflow.

## Verified revision

Code commit `f6d86dc1` passed [CI run 35201844746](https://github.com/Milky2018/wasmoon/actions/runs/35201844746)
on 2026-09-17. All five jobs succeeded: Linux AMD64, macOS ARM64,
Windows AMD64 with MSVC and Clang, and Linux ASan/UBSan. The expanded
HTTP CLI runner passed with both engines in all four platform configurations.

Local verification also passed with the freshly installed release executable,
along with CLI behavior regressions, strict MoonBit warning checks and all
2,522 project-wide native tests. These counts do not represent HTTP-only coverage.

## Limits of this audit

This is a stronger targeted functional regression suite, not exhaustive RFC/WIT
conformance or production certification. It does not establish long-running
memory stability, sustained saturation behavior, every cancellation race, or
interoperability with a broad corpus of independently compiled language-SDK
guests. The negative startup check validates the declared handler export;
full linking and initialization still occur per connection. Transport limits
remain documented in `modules/wasmoon/wasi_http/README.md`.
