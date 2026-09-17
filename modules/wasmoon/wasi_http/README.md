# WASI HTTP 0.3

`HttpHost` implements the official `wasi:http/service`, `wasi:http/client` and
`wasi:http/middleware` contracts at version 0.3.0. The CLI uses a fresh component
instance per connection; embedders own the linker and its lifetime.

## Running a service

```sh
wasmoon serve service.wasm --addr 127.0.0.1:8080
wasmoon serve service.wasm --no-jit
wasmoon serve service.wasm --middleware outer.wasm --middleware inner.wasm
wasmoon serve proxy.wasm --network loopback
```

Middleware options are ordered from outermost to innermost. All layers share
HTTP resource identities and forward requests directly through their handler
imports. They do not serialize messages through a local network connection.

Outgoing network access is denied by default. `--network loopback` checks the
resolved destination address; `--network all` grants unrestricted outgoing HTTP
access. These policies apply independently of an inbound request's Host field.
The embedding API accepts separate authority and resolved-address predicates.
Redirects are returned to the guest, never automatically followed.

## Embedding

Create a `ComponentLinker`, then an `HttpHost` for that linker. Register
`add_types`, `add_service_base` and either `add_network_client` or `add_client`.
Run instantiation and requests inside `host.run`. `serve_connection` accepts one
HTTP/1.1 connection; the caller owns and closes the socket. `add_downstream`
registers a previously instantiated service before instantiating its middleware.
`add_handler` also accepts a custom asynchronous host implementation.

The base service imports include clocks, randomness, EOF stdin, and asynchronous
stdout/stderr. Embedders may provide their own async writers to
`add_service_base`. Clock waits and network operations use the same reactor;
there is no periodic readiness polling.

Call `linker.close()` after the HTTP task scope exits. Scope cancellation joins
network tasks, cancels pending invocations and releases outstanding body
transfers. A guest may publish its response before its callback exits; the driver
continues executing that callback until its streaming work completes.

## Message semantics

Fields preserve duplicate entries, original name spelling, order and arbitrary
allowed byte values. Lookup is case insensitive. CR/LF injection and invalid
names are rejected; mutation of immutable headers fails. Field sections are
limited to 64 KiB and 1024 entries. Hop-by-hop fields are managed by the transport.

Bodies are streams, with a bounded 64 KiB buffer per transfer. Reading and writing
apply backpressure; trailers become available after stream EOF. Transmission
completion waits for the consumer receipt. Dropping a body cancels its producer;
undelivered trailer resources are reclaimed. Immutable request-options children
block parent destruction and ownership transfer; consuming the body keeps those
children valid as required by WIT. Content-Length is checked against
the bytes transmitted, and conflicting framing is rejected.

The client supports HTTP and HTTPS with certificate verification against system
trust roots by default. Embedders can choose custom trust roots through
`add_network_client`. Connection, first-byte and between-byte timeouts follow
request options; defaults are 30 seconds. TLS backend errors currently map to
`TLS-protocol-error` because moonbitlang/async exposes an unstructured TLS error;
certificate verification failures still fail the request.

## Transport scope

The built-in transport serves HTTP/1.1 and accepts HTTP/1.0 or HTTP/1.1 responses.
It closes each connection after one exchange. HTTP/2, HTTP/3, connection pooling,
protocol upgrades and CONNECT tunnels are not implemented. HTTPS is supported
for outgoing requests; terminate inbound TLS at a reverse proxy. These are
transport choices, not additional WIT imports or a substitute for the async
Component Model contract. Resource limits here do not provide CPU/memory
isolation for untrusted guest computation.

## Contracts and tests

The HTTP WIT files come unchanged from WebAssembly/WASI tag `v0.3.0`, commit
`3ee2a590c766594ae44a54730fc74fc27da5c609`, under `proposals/http/wit`.
Dependency WIT files match Wasmoon's existing pinned Preview 3 snapshot.
The upstream W3C Community Contributor License notice is preserved in
`wit/LICENSE.md`; see also the repository's third-party notices.

```sh
python3 modules/wasmoon/wasi_http/generate_contracts.py --verify-wit --check
moon test --target native modules/wasmoon/wasi_http
python3 scripts/test_wasi_http.py --wasmoon ./wasmoon
```

The real guests are encoded and validated by wasm-tools 1.254.0 from official
WIT. The runner exercises both engines, observable middleware ordering, guest-visible
request metadata, outgoing proxy requests, capability denial, large streaming
bodies, duplicate trailers, concurrent requests, and 300 abandoned uploads per
server configuration. Raw-socket cases verify incremental responses before
upload EOF, case-insensitive Expect handling, absolute-form targets, valid and
invalid chunk extensions, HEAD, OPTIONS, startup rejection of missing handler
exports, occupied ports, and continued service after guest traps. Unit tests cover
field/resource behavior, transmission receipts, cancellation, timeouts and TLS
trust verification. CI runs native tests and the CLI suite on Linux, macOS,
Windows Clang and Windows MSVC.
