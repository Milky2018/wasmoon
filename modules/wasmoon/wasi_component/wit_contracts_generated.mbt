// Generated from the pinned official WIT snapshots.
// DO NOT EDIT. Update wit/ and run a Moon development command.

///|
let wasi_preview2_wit_sha256 : String = "b349a9c4d0b68e5e0943d355a9b8c282d9f320ce90a084a4ee44435feb276f8f"

///|
fn wasi_preview2_resource_names() -> Array[String] {
  [
    "wasi:cli@0.2.11/terminal-input.terminal-input",
    "wasi:cli@0.2.11/terminal-output.terminal-output",
    "wasi:filesystem@0.2.11/types.descriptor",
    "wasi:filesystem@0.2.11/types.directory-entry-stream",
    "wasi:io@0.2.11/error.error",
    "wasi:io@0.2.11/poll.pollable",
    "wasi:io@0.2.11/streams.input-stream",
    "wasi:io@0.2.11/streams.output-stream",
    "wasi:sockets@0.2.11/ip-name-lookup.resolve-address-stream",
    "wasi:sockets@0.2.11/network.network",
    "wasi:sockets@0.2.11/tcp.tcp-socket",
    "wasi:sockets@0.2.11/udp.incoming-datagram-stream",
    "wasi:sockets@0.2.11/udp.outgoing-datagram-stream",
    "wasi:sockets@0.2.11/udp.udp-socket",
  ]
}

///|
fn wasi_preview2_type_space(
  resolve_resource : (String) -> @component.TypeDef?,
) -> Array[@component.TypeDef?] {
  [
    resolve_resource("wasi:io@0.2.11/error.error"),
    Some(Borrow(0)),
    resolve_resource("wasi:io@0.2.11/poll.pollable"),
    Some(Borrow(2)),
    Some(List(TypeIdx(3))),
    Some(List(Prim(U32))),
    resolve_resource("wasi:io@0.2.11/error.error"),
    resolve_resource("wasi:io@0.2.11/poll.pollable"),
    Some(Own(6)),
    Some(Variant([{ label: "last-operation-failed", ty: Some(TypeIdx(8)), refines: None }, { label: "closed", ty: None, refines: None }])),
    resolve_resource("wasi:io@0.2.11/streams.input-stream"),
    resolve_resource("wasi:io@0.2.11/streams.output-stream"),
    Some(Borrow(10)),
    Some(List(Prim(U8))),
    Some(Result(Some(TypeIdx(13)), Some(TypeIdx(9)))),
    Some(Result(Some(Prim(U64)), Some(TypeIdx(9)))),
    Some(Borrow(11)),
    Some(Result(None, Some(TypeIdx(9)))),
    Some(Own(7)),
    resolve_resource("wasi:io@0.2.11/poll.pollable"),
    Some(DefValType(U64)),
    Some(DefValType(U64)),
    Some(Record([{ label: "seconds", ty: Prim(U64) }, { label: "nanoseconds", ty: Prim(U32) }])),
    Some(Own(19)),
    resolve_resource("wasi:io@0.2.11/streams.input-stream"),
    resolve_resource("wasi:io@0.2.11/streams.output-stream"),
    resolve_resource("wasi:io@0.2.11/error.error"),
    Some(Record([{ label: "seconds", ty: Prim(U64) }, { label: "nanoseconds", ty: Prim(U32) }])),
    Some(DefValType(U64)),
    Some(Enum(["unknown", "block-device", "character-device", "directory", "fifo", "symbolic-link", "regular-file", "socket"])),
    Some(Flags(["read", "write", "file-integrity-sync", "data-integrity-sync", "requested-write-sync", "mutate-directory"])),
    Some(Flags(["symlink-follow"])),
    Some(Flags(["create", "directory", "exclusive", "truncate"])),
    Some(DefValType(U64)),
    Some(Option(TypeIdx(27))),
    Some(Record([{ label: "type", ty: TypeIdx(29) }, { label: "link-count", ty: TypeIdx(33) }, { label: "size", ty: TypeIdx(28) }, { label: "data-access-timestamp", ty: TypeIdx(34) }, { label: "data-modification-timestamp", ty: TypeIdx(34) }, { label: "status-change-timestamp", ty: TypeIdx(34) }])),
    Some(Variant([{ label: "no-change", ty: None, refines: None }, { label: "now", ty: None, refines: None }, { label: "timestamp", ty: Some(TypeIdx(27)), refines: None }])),
    Some(Record([{ label: "type", ty: TypeIdx(29) }, { label: "name", ty: Prim(String) }])),
    Some(Enum(["access", "would-block", "already", "bad-descriptor", "busy", "deadlock", "quota", "exist", "file-too-large", "illegal-byte-sequence", "in-progress", "interrupted", "invalid", "io", "is-directory", "loop", "too-many-links", "message-size", "name-too-long", "no-device", "no-entry", "no-lock", "insufficient-memory", "insufficient-space", "not-directory", "not-empty", "not-recoverable", "unsupported", "no-tty", "no-such-device", "overflow", "not-permitted", "pipe", "read-only", "invalid-seek", "text-file-busy", "cross-device"])),
    Some(Enum(["normal", "sequential", "random", "will-need", "dont-need", "no-reuse"])),
    Some(Record([{ label: "lower", ty: Prim(U64) }, { label: "upper", ty: Prim(U64) }])),
    resolve_resource("wasi:filesystem@0.2.11/types.descriptor"),
    resolve_resource("wasi:filesystem@0.2.11/types.directory-entry-stream"),
    Some(Borrow(41)),
    Some(Own(24)),
    Some(Result(Some(TypeIdx(44)), Some(TypeIdx(38)))),
    Some(Own(25)),
    Some(Result(Some(TypeIdx(46)), Some(TypeIdx(38)))),
    Some(Result(None, Some(TypeIdx(38)))),
    Some(Result(Some(TypeIdx(30)), Some(TypeIdx(38)))),
    Some(Result(Some(TypeIdx(29)), Some(TypeIdx(38)))),
    Some(List(Prim(U8))),
    Some(Tuple([TypeIdx(51), Prim(Bool)])),
    Some(Result(Some(TypeIdx(52)), Some(TypeIdx(38)))),
    Some(Result(Some(TypeIdx(28)), Some(TypeIdx(38)))),
    Some(Own(42)),
    Some(Result(Some(TypeIdx(55)), Some(TypeIdx(38)))),
    Some(Result(Some(TypeIdx(35)), Some(TypeIdx(38)))),
    Some(Own(41)),
    Some(Result(Some(TypeIdx(58)), Some(TypeIdx(38)))),
    Some(Result(Some(Prim(String)), Some(TypeIdx(38)))),
    Some(Result(Some(TypeIdx(40)), Some(TypeIdx(38)))),
    Some(Borrow(42)),
    Some(Option(TypeIdx(37))),
    Some(Result(Some(TypeIdx(63)), Some(TypeIdx(38)))),
    Some(Borrow(26)),
    Some(Option(TypeIdx(38))),
    resolve_resource("wasi:filesystem@0.2.11/types.descriptor"),
    Some(Own(67)),
    Some(Tuple([TypeIdx(68), Prim(String)])),
    Some(List(TypeIdx(69))),
    resolve_resource("wasi:sockets@0.2.11/network.network"),
    Some(Enum(["unknown", "access-denied", "not-supported", "invalid-argument", "out-of-memory", "timeout", "concurrency-conflict", "not-in-progress", "would-block", "invalid-state", "new-socket-limit", "address-not-bindable", "address-in-use", "remote-unreachable", "connection-refused", "connection-reset", "connection-aborted", "datagram-too-large", "name-unresolvable", "temporary-resolver-failure", "permanent-resolver-failure"])),
    Some(Enum(["ipv4", "ipv6"])),
    Some(Tuple([Prim(U8), Prim(U8), Prim(U8), Prim(U8)])),
    Some(Tuple([Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16)])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(74)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(75)), refines: None }])),
    Some(Record([{ label: "port", ty: Prim(U16) }, { label: "address", ty: TypeIdx(74) }])),
    Some(Record([{ label: "port", ty: Prim(U16) }, { label: "flow-info", ty: Prim(U32) }, { label: "address", ty: TypeIdx(75) }, { label: "scope-id", ty: Prim(U32) }])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(77)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(78)), refines: None }])),
    Some(Option(TypeIdx(72))),
    resolve_resource("wasi:sockets@0.2.11/network.network"),
    resolve_resource("wasi:io@0.2.11/poll.pollable"),
    resolve_resource("wasi:sockets@0.2.11/network.network"),
    Some(Enum(["unknown", "access-denied", "not-supported", "invalid-argument", "out-of-memory", "timeout", "concurrency-conflict", "not-in-progress", "would-block", "invalid-state", "new-socket-limit", "address-not-bindable", "address-in-use", "remote-unreachable", "connection-refused", "connection-reset", "connection-aborted", "datagram-too-large", "name-unresolvable", "temporary-resolver-failure", "permanent-resolver-failure"])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(74)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(75)), refines: None }])),
    resolve_resource("wasi:sockets@0.2.11/ip-name-lookup.resolve-address-stream"),
    Some(Borrow(83)),
    Some(Own(86)),
    Some(Result(Some(TypeIdx(88)), Some(TypeIdx(84)))),
    Some(Borrow(86)),
    Some(Option(TypeIdx(85))),
    Some(Result(Some(TypeIdx(91)), Some(TypeIdx(84)))),
    resolve_resource("wasi:io@0.2.11/streams.input-stream"),
    resolve_resource("wasi:io@0.2.11/streams.output-stream"),
    resolve_resource("wasi:io@0.2.11/poll.pollable"),
    Some(DefValType(U64)),
    resolve_resource("wasi:sockets@0.2.11/network.network"),
    Some(Enum(["unknown", "access-denied", "not-supported", "invalid-argument", "out-of-memory", "timeout", "concurrency-conflict", "not-in-progress", "would-block", "invalid-state", "new-socket-limit", "address-not-bindable", "address-in-use", "remote-unreachable", "connection-refused", "connection-reset", "connection-aborted", "datagram-too-large", "name-unresolvable", "temporary-resolver-failure", "permanent-resolver-failure"])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(77)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(78)), refines: None }])),
    Some(Enum(["ipv4", "ipv6"])),
    Some(Enum(["receive", "send", "both"])),
    resolve_resource("wasi:sockets@0.2.11/tcp.tcp-socket"),
    Some(Borrow(102)),
    Some(Borrow(97)),
    Some(Result(None, Some(TypeIdx(98)))),
    Some(Own(93)),
    Some(Own(94)),
    Some(Tuple([TypeIdx(106), TypeIdx(107)])),
    Some(Result(Some(TypeIdx(108)), Some(TypeIdx(98)))),
    Some(Own(102)),
    Some(Tuple([TypeIdx(110), TypeIdx(106), TypeIdx(107)])),
    Some(Result(Some(TypeIdx(111)), Some(TypeIdx(98)))),
    Some(Result(Some(TypeIdx(99)), Some(TypeIdx(98)))),
    Some(Result(Some(Prim(Bool)), Some(TypeIdx(98)))),
    Some(Result(Some(TypeIdx(96)), Some(TypeIdx(98)))),
    Some(Result(Some(Prim(U32)), Some(TypeIdx(98)))),
    Some(Result(Some(Prim(U8)), Some(TypeIdx(98)))),
    Some(Result(Some(Prim(U64)), Some(TypeIdx(98)))),
    resolve_resource("wasi:sockets@0.2.11/network.network"),
    Some(Enum(["unknown", "access-denied", "not-supported", "invalid-argument", "out-of-memory", "timeout", "concurrency-conflict", "not-in-progress", "would-block", "invalid-state", "new-socket-limit", "address-not-bindable", "address-in-use", "remote-unreachable", "connection-refused", "connection-reset", "connection-aborted", "datagram-too-large", "name-unresolvable", "temporary-resolver-failure", "permanent-resolver-failure"])),
    Some(Enum(["ipv4", "ipv6"])),
    resolve_resource("wasi:sockets@0.2.11/tcp.tcp-socket"),
    Some(Own(122)),
    Some(Result(Some(TypeIdx(123)), Some(TypeIdx(120)))),
    resolve_resource("wasi:io@0.2.11/poll.pollable"),
    resolve_resource("wasi:sockets@0.2.11/network.network"),
    Some(Enum(["unknown", "access-denied", "not-supported", "invalid-argument", "out-of-memory", "timeout", "concurrency-conflict", "not-in-progress", "would-block", "invalid-state", "new-socket-limit", "address-not-bindable", "address-in-use", "remote-unreachable", "connection-refused", "connection-reset", "connection-aborted", "datagram-too-large", "name-unresolvable", "temporary-resolver-failure", "permanent-resolver-failure"])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(77)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(78)), refines: None }])),
    Some(Enum(["ipv4", "ipv6"])),
    Some(List(Prim(U8))),
    Some(Record([{ label: "data", ty: TypeIdx(130) }, { label: "remote-address", ty: TypeIdx(128) }])),
    Some(Option(TypeIdx(128))),
    Some(Record([{ label: "data", ty: TypeIdx(130) }, { label: "remote-address", ty: TypeIdx(132) }])),
    resolve_resource("wasi:sockets@0.2.11/udp.udp-socket"),
    resolve_resource("wasi:sockets@0.2.11/udp.incoming-datagram-stream"),
    resolve_resource("wasi:sockets@0.2.11/udp.outgoing-datagram-stream"),
    Some(Borrow(134)),
    Some(Borrow(126)),
    Some(Result(None, Some(TypeIdx(127)))),
    Some(Own(135)),
    Some(Own(136)),
    Some(Tuple([TypeIdx(140), TypeIdx(141)])),
    Some(Result(Some(TypeIdx(142)), Some(TypeIdx(127)))),
    Some(Result(Some(TypeIdx(128)), Some(TypeIdx(127)))),
    Some(Result(Some(Prim(U8)), Some(TypeIdx(127)))),
    Some(Result(Some(Prim(U64)), Some(TypeIdx(127)))),
    Some(Borrow(135)),
    Some(List(TypeIdx(131))),
    Some(Result(Some(TypeIdx(148)), Some(TypeIdx(127)))),
    Some(Borrow(136)),
    Some(List(TypeIdx(133))),
    resolve_resource("wasi:sockets@0.2.11/network.network"),
    Some(Enum(["unknown", "access-denied", "not-supported", "invalid-argument", "out-of-memory", "timeout", "concurrency-conflict", "not-in-progress", "would-block", "invalid-state", "new-socket-limit", "address-not-bindable", "address-in-use", "remote-unreachable", "connection-refused", "connection-reset", "connection-aborted", "datagram-too-large", "name-unresolvable", "temporary-resolver-failure", "permanent-resolver-failure"])),
    Some(Enum(["ipv4", "ipv6"])),
    resolve_resource("wasi:sockets@0.2.11/udp.udp-socket"),
    Some(Own(155)),
    Some(Result(Some(TypeIdx(156)), Some(TypeIdx(153)))),
    Some(Own(81)),
    Some(Own(82)),
    Some(Own(95)),
    Some(Own(125)),
    Some(Tuple([Prim(U64), Prim(U64)])),
    Some(List(Prim(U8))),
    Some(Tuple([Prim(String), Prim(String)])),
    Some(List(TypeIdx(164))),
    Some(List(Prim(String))),
    Some(Option(Prim(String))),
    Some(Result(None, None)),
    resolve_resource("wasi:io@0.2.11/streams.input-stream"),
    resolve_resource("wasi:io@0.2.11/streams.output-stream"),
    resolve_resource("wasi:io@0.2.11/streams.output-stream"),
    resolve_resource("wasi:cli@0.2.11/terminal-input.terminal-input"),
    resolve_resource("wasi:cli@0.2.11/terminal-output.terminal-output"),
    resolve_resource("wasi:cli@0.2.11/terminal-input.terminal-input"),
    Some(Own(174)),
    Some(Option(TypeIdx(175))),
    resolve_resource("wasi:cli@0.2.11/terminal-output.terminal-output"),
    Some(Own(177)),
    Some(Option(TypeIdx(178))),
    resolve_resource("wasi:cli@0.2.11/terminal-output.terminal-output"),
    Some(Own(180)),
    Some(Option(TypeIdx(181))),
    Some(Own(169)),
    Some(Own(170)),
    Some(Own(171)),
  ]
}

///|
fn wasi_preview2_func_type(
  interface : String,
  function : String,
) -> @component.FuncType? {
  match "\{interface}#\{function}" {
    "wasi:io@0.2.11/error#[method]error.to-debug-string" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(1) }], result: Some(Prim(String)) })
    "wasi:io@0.2.11/poll#[method]pollable.ready" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(3) }], result: Some(Prim(Bool)) })
    "wasi:io@0.2.11/poll#[method]pollable.block" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(3) }], result: None })
    "wasi:io@0.2.11/poll#poll" => Some({ is_async: false, params: [{ label: "in", ty: TypeIdx(4) }], result: Some(TypeIdx(5)) })
    "wasi:io@0.2.11/streams#[method]input-stream.read" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(12) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(14)) })
    "wasi:io@0.2.11/streams#[method]input-stream.blocking-read" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(12) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(14)) })
    "wasi:io@0.2.11/streams#[method]input-stream.skip" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(12) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(15)) })
    "wasi:io@0.2.11/streams#[method]input-stream.blocking-skip" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(12) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(15)) })
    "wasi:io@0.2.11/streams#[method]input-stream.subscribe" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(12) }], result: Some(TypeIdx(18)) })
    "wasi:io@0.2.11/streams#[method]output-stream.check-write" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }], result: Some(TypeIdx(15)) })
    "wasi:io@0.2.11/streams#[method]output-stream.write" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }, { label: "contents", ty: TypeIdx(13) }], result: Some(TypeIdx(17)) })
    "wasi:io@0.2.11/streams#[method]output-stream.blocking-write-and-flush" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }, { label: "contents", ty: TypeIdx(13) }], result: Some(TypeIdx(17)) })
    "wasi:io@0.2.11/streams#[method]output-stream.flush" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }], result: Some(TypeIdx(17)) })
    "wasi:io@0.2.11/streams#[method]output-stream.blocking-flush" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }], result: Some(TypeIdx(17)) })
    "wasi:io@0.2.11/streams#[method]output-stream.subscribe" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }], result: Some(TypeIdx(18)) })
    "wasi:io@0.2.11/streams#[method]output-stream.write-zeroes" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(17)) })
    "wasi:io@0.2.11/streams#[method]output-stream.blocking-write-zeroes-and-flush" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(17)) })
    "wasi:io@0.2.11/streams#[method]output-stream.splice" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }, { label: "src", ty: TypeIdx(12) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(15)) })
    "wasi:io@0.2.11/streams#[method]output-stream.blocking-splice" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(16) }, { label: "src", ty: TypeIdx(12) }, { label: "len", ty: Prim(U64) }], result: Some(TypeIdx(15)) })
    "wasi:clocks@0.2.11/monotonic-clock#now" => Some({ is_async: false, params: [], result: Some(TypeIdx(20)) })
    "wasi:clocks@0.2.11/monotonic-clock#resolution" => Some({ is_async: false, params: [], result: Some(TypeIdx(21)) })
    "wasi:clocks@0.2.11/monotonic-clock#subscribe-instant" => Some({ is_async: false, params: [{ label: "when", ty: TypeIdx(20) }], result: Some(TypeIdx(23)) })
    "wasi:clocks@0.2.11/monotonic-clock#subscribe-duration" => Some({ is_async: false, params: [{ label: "when", ty: TypeIdx(21) }], result: Some(TypeIdx(23)) })
    "wasi:clocks@0.2.11/wall-clock#now" => Some({ is_async: false, params: [], result: Some(TypeIdx(22)) })
    "wasi:clocks@0.2.11/wall-clock#resolution" => Some({ is_async: false, params: [], result: Some(TypeIdx(22)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.read-via-stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "offset", ty: TypeIdx(28) }], result: Some(TypeIdx(45)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.write-via-stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "offset", ty: TypeIdx(28) }], result: Some(TypeIdx(47)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.append-via-stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(47)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.advise" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "offset", ty: TypeIdx(28) }, { label: "length", ty: TypeIdx(28) }, { label: "advice", ty: TypeIdx(39) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.sync-data" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.get-flags" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(49)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.get-type" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(50)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.set-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "size", ty: TypeIdx(28) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.set-times" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "data-access-timestamp", ty: TypeIdx(36) }, { label: "data-modification-timestamp", ty: TypeIdx(36) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.read" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "length", ty: TypeIdx(28) }, { label: "offset", ty: TypeIdx(28) }], result: Some(TypeIdx(53)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.write" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "buffer", ty: TypeIdx(51) }, { label: "offset", ty: TypeIdx(28) }], result: Some(TypeIdx(54)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.read-directory" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(56)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.sync" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.create-directory-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.stat" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(57)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.stat-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path-flags", ty: TypeIdx(31) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(57)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.set-times-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path-flags", ty: TypeIdx(31) }, { label: "path", ty: Prim(String) }, { label: "data-access-timestamp", ty: TypeIdx(36) }, { label: "data-modification-timestamp", ty: TypeIdx(36) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.link-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "old-path-flags", ty: TypeIdx(31) }, { label: "old-path", ty: Prim(String) }, { label: "new-descriptor", ty: TypeIdx(43) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.open-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path-flags", ty: TypeIdx(31) }, { label: "path", ty: Prim(String) }, { label: "open-flags", ty: TypeIdx(32) }, { label: "flags", ty: TypeIdx(30) }], result: Some(TypeIdx(59)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.readlink-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(60)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.remove-directory-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.rename-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "old-path", ty: Prim(String) }, { label: "new-descriptor", ty: TypeIdx(43) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.symlink-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "old-path", ty: Prim(String) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.unlink-file-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(48)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.is-same-object" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "other", ty: TypeIdx(43) }], result: Some(Prim(Bool)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.metadata-hash" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }], result: Some(TypeIdx(61)) })
    "wasi:filesystem@0.2.11/types#[method]descriptor.metadata-hash-at" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(43) }, { label: "path-flags", ty: TypeIdx(31) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(61)) })
    "wasi:filesystem@0.2.11/types#[method]directory-entry-stream.read-directory-entry" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(62) }], result: Some(TypeIdx(64)) })
    "wasi:filesystem@0.2.11/types#filesystem-error-code" => Some({ is_async: false, params: [{ label: "err", ty: TypeIdx(65) }], result: Some(TypeIdx(66)) })
    "wasi:filesystem@0.2.11/preopens#get-directories" => Some({ is_async: false, params: [], result: Some(TypeIdx(70)) })
    "wasi:sockets@0.2.11/instance-network#instance-network" => Some({ is_async: false, params: [], result: Some(TypeIdx(158)) })
    "wasi:sockets@0.2.11/ip-name-lookup#resolve-addresses" => Some({ is_async: false, params: [{ label: "network", ty: TypeIdx(87) }, { label: "name", ty: Prim(String) }], result: Some(TypeIdx(89)) })
    "wasi:sockets@0.2.11/ip-name-lookup#[method]resolve-address-stream.resolve-next-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(90) }], result: Some(TypeIdx(92)) })
    "wasi:sockets@0.2.11/ip-name-lookup#[method]resolve-address-stream.subscribe" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(90) }], result: Some(TypeIdx(159)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.start-bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "network", ty: TypeIdx(104) }, { label: "local-address", ty: TypeIdx(99) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.finish-bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.start-connect" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "network", ty: TypeIdx(104) }, { label: "remote-address", ty: TypeIdx(99) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.finish-connect" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(109)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.start-listen" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.finish-listen" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.accept" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(112)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.local-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(113)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.remote-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(113)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.is-listening" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(Prim(Bool)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.address-family" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(100)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-listen-backlog-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.keep-alive-enabled" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(114)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-keep-alive-enabled" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: Prim(Bool) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.keep-alive-idle-time" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(115)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-keep-alive-idle-time" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: TypeIdx(96) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.keep-alive-interval" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(115)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-keep-alive-interval" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: TypeIdx(96) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.keep-alive-count" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(116)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-keep-alive-count" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: Prim(U32) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(117)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: Prim(U8) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(118)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(118)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.set-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.subscribe" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }], result: Some(TypeIdx(160)) })
    "wasi:sockets@0.2.11/tcp#[method]tcp-socket.shutdown" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(103) }, { label: "shutdown-type", ty: TypeIdx(101) }], result: Some(TypeIdx(105)) })
    "wasi:sockets@0.2.11/tcp-create-socket#create-tcp-socket" => Some({ is_async: false, params: [{ label: "address-family", ty: TypeIdx(121) }], result: Some(TypeIdx(124)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.start-bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }, { label: "network", ty: TypeIdx(138) }, { label: "local-address", ty: TypeIdx(128) }], result: Some(TypeIdx(139)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.finish-bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(139)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }, { label: "remote-address", ty: TypeIdx(132) }], result: Some(TypeIdx(143)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.local-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(144)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.remote-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(144)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.address-family" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(129)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.unicast-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(145)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.set-unicast-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }, { label: "value", ty: Prim(U8) }], result: Some(TypeIdx(139)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(146)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.set-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(139)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(146)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.set-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(139)) })
    "wasi:sockets@0.2.11/udp#[method]udp-socket.subscribe" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(137) }], result: Some(TypeIdx(161)) })
    "wasi:sockets@0.2.11/udp#[method]incoming-datagram-stream.receive" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(147) }, { label: "max-results", ty: Prim(U64) }], result: Some(TypeIdx(149)) })
    "wasi:sockets@0.2.11/udp#[method]incoming-datagram-stream.subscribe" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(147) }], result: Some(TypeIdx(161)) })
    "wasi:sockets@0.2.11/udp#[method]outgoing-datagram-stream.check-send" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(150) }], result: Some(TypeIdx(146)) })
    "wasi:sockets@0.2.11/udp#[method]outgoing-datagram-stream.send" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(150) }, { label: "datagrams", ty: TypeIdx(151) }], result: Some(TypeIdx(146)) })
    "wasi:sockets@0.2.11/udp#[method]outgoing-datagram-stream.subscribe" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(150) }], result: Some(TypeIdx(161)) })
    "wasi:sockets@0.2.11/udp-create-socket#create-udp-socket" => Some({ is_async: false, params: [{ label: "address-family", ty: TypeIdx(154) }], result: Some(TypeIdx(157)) })
    "wasi:random@0.2.11/insecure-seed#insecure-seed" => Some({ is_async: false, params: [], result: Some(TypeIdx(162)) })
    "wasi:random@0.2.11/insecure#get-insecure-random-bytes" => Some({ is_async: false, params: [{ label: "len", ty: Prim(U64) }], result: Some(TypeIdx(163)) })
    "wasi:random@0.2.11/insecure#get-insecure-random-u64" => Some({ is_async: false, params: [], result: Some(Prim(U64)) })
    "wasi:random@0.2.11/random#get-random-bytes" => Some({ is_async: false, params: [{ label: "len", ty: Prim(U64) }], result: Some(TypeIdx(163)) })
    "wasi:random@0.2.11/random#get-random-u64" => Some({ is_async: false, params: [], result: Some(Prim(U64)) })
    "wasi:cli@0.2.11/environment#get-environment" => Some({ is_async: false, params: [], result: Some(TypeIdx(165)) })
    "wasi:cli@0.2.11/environment#get-arguments" => Some({ is_async: false, params: [], result: Some(TypeIdx(166)) })
    "wasi:cli@0.2.11/environment#initial-cwd" => Some({ is_async: false, params: [], result: Some(TypeIdx(167)) })
    "wasi:cli@0.2.11/exit#exit" => Some({ is_async: false, params: [{ label: "status", ty: TypeIdx(168) }], result: None })
    "wasi:cli@0.2.11/run#run" => Some({ is_async: false, params: [], result: Some(TypeIdx(168)) })
    "wasi:cli@0.2.11/stdin#get-stdin" => Some({ is_async: false, params: [], result: Some(TypeIdx(183)) })
    "wasi:cli@0.2.11/stdout#get-stdout" => Some({ is_async: false, params: [], result: Some(TypeIdx(184)) })
    "wasi:cli@0.2.11/stderr#get-stderr" => Some({ is_async: false, params: [], result: Some(TypeIdx(185)) })
    "wasi:cli@0.2.11/terminal-stdin#get-terminal-stdin" => Some({ is_async: false, params: [], result: Some(TypeIdx(176)) })
    "wasi:cli@0.2.11/terminal-stdout#get-terminal-stdout" => Some({ is_async: false, params: [], result: Some(TypeIdx(179)) })
    "wasi:cli@0.2.11/terminal-stderr#get-terminal-stderr" => Some({ is_async: false, params: [], result: Some(TypeIdx(182)) })
    _ => None
  }
}

///|
fn wasi_preview2_exported_types(
  interface : String,
) -> Array[(String, Int)] {
  match interface {
    "wasi:io@0.2.11/error" => [("error", 0)]
    "wasi:io@0.2.11/poll" => [("pollable", 2)]
    "wasi:io@0.2.11/streams" => [("error", 6), ("pollable", 7), ("stream-error", 9), ("input-stream", 10), ("output-stream", 11)]
    "wasi:clocks@0.2.11/monotonic-clock" => [("pollable", 19), ("instant", 20), ("duration", 21)]
    "wasi:clocks@0.2.11/wall-clock" => [("datetime", 22)]
    "wasi:filesystem@0.2.11/types" => [("input-stream", 24), ("output-stream", 25), ("error", 26), ("datetime", 27), ("filesize", 28), ("descriptor-type", 29), ("descriptor-flags", 30), ("path-flags", 31), ("open-flags", 32), ("link-count", 33), ("descriptor-stat", 35), ("new-timestamp", 36), ("directory-entry", 37), ("error-code", 38), ("advice", 39), ("metadata-hash-value", 40), ("descriptor", 41), ("directory-entry-stream", 42)]
    "wasi:filesystem@0.2.11/preopens" => [("descriptor", 67)]
    "wasi:sockets@0.2.11/network" => [("network", 71), ("error-code", 72), ("ip-address-family", 73), ("ipv4-address", 74), ("ipv6-address", 75), ("ip-address", 76), ("ipv4-socket-address", 77), ("ipv6-socket-address", 78), ("ip-socket-address", 79)]
    "wasi:sockets@0.2.11/instance-network" => [("network", 81)]
    "wasi:sockets@0.2.11/ip-name-lookup" => [("pollable", 82), ("network", 83), ("error-code", 84), ("ip-address", 85), ("resolve-address-stream", 86)]
    "wasi:sockets@0.2.11/tcp" => [("input-stream", 93), ("output-stream", 94), ("pollable", 95), ("duration", 96), ("network", 97), ("error-code", 98), ("ip-socket-address", 99), ("ip-address-family", 100), ("shutdown-type", 101), ("tcp-socket", 102)]
    "wasi:sockets@0.2.11/tcp-create-socket" => [("network", 119), ("error-code", 120), ("ip-address-family", 121), ("tcp-socket", 122)]
    "wasi:sockets@0.2.11/udp" => [("pollable", 125), ("network", 126), ("error-code", 127), ("ip-socket-address", 128), ("ip-address-family", 129), ("incoming-datagram", 131), ("outgoing-datagram", 133), ("udp-socket", 134), ("incoming-datagram-stream", 135), ("outgoing-datagram-stream", 136)]
    "wasi:sockets@0.2.11/udp-create-socket" => [("network", 152), ("error-code", 153), ("ip-address-family", 154), ("udp-socket", 155)]
    "wasi:random@0.2.11/insecure-seed" => []
    "wasi:random@0.2.11/insecure" => []
    "wasi:random@0.2.11/random" => []
    "wasi:cli@0.2.11/environment" => []
    "wasi:cli@0.2.11/exit" => []
    "wasi:cli@0.2.11/run" => []
    "wasi:cli@0.2.11/stdin" => [("input-stream", 169)]
    "wasi:cli@0.2.11/stdout" => [("output-stream", 170)]
    "wasi:cli@0.2.11/stderr" => [("output-stream", 171)]
    "wasi:cli@0.2.11/terminal-input" => [("terminal-input", 172)]
    "wasi:cli@0.2.11/terminal-output" => [("terminal-output", 173)]
    "wasi:cli@0.2.11/terminal-stdin" => [("terminal-input", 174)]
    "wasi:cli@0.2.11/terminal-stdout" => [("terminal-output", 177)]
    "wasi:cli@0.2.11/terminal-stderr" => [("terminal-output", 180)]
    _ => []
  }
}

///|
let wasi_preview3_wit_sha256 : String = "40406e7432b7e3213b083d0bcb308676927c97fc488acaaf6c179f1a9e64124b"

///|
fn wasi_preview3_resource_names() -> Array[String] {
  [
    "wasi:cli@0.3.0/terminal-input.terminal-input",
    "wasi:cli@0.3.0/terminal-output.terminal-output",
    "wasi:filesystem@0.3.0/types.descriptor",
    "wasi:sockets@0.3.0/types.tcp-socket",
    "wasi:sockets@0.3.0/types.udp-socket",
  ]
}

///|
fn wasi_preview3_type_space(
  resolve_resource : (String) -> @component.TypeDef?,
) -> Array[@component.TypeDef?] {
  [
    Some(DefValType(U64)),
    Some(DefValType(U64)),
    Some(DefValType(U64)),
    Some(DefValType(U64)),
    Some(Record([{ label: "seconds", ty: Prim(S64) }, { label: "nanoseconds", ty: Prim(U32) }])),
    Some(Option(Prim(String))),
    Some(Option(Prim(S64))),
    Some(Record([{ label: "seconds", ty: Prim(S64) }, { label: "nanoseconds", ty: Prim(U32) }])),
    Some(DefValType(U64)),
    Some(Option(Prim(String))),
    Some(Variant([{ label: "block-device", ty: None, refines: None }, { label: "character-device", ty: None, refines: None }, { label: "directory", ty: None, refines: None }, { label: "fifo", ty: None, refines: None }, { label: "symbolic-link", ty: None, refines: None }, { label: "regular-file", ty: None, refines: None }, { label: "socket", ty: None, refines: None }, { label: "other", ty: Some(TypeIdx(9)), refines: None }])),
    Some(Flags(["read", "write", "file-integrity-sync", "data-integrity-sync", "requested-write-sync", "mutate-directory"])),
    Some(Flags(["symlink-follow"])),
    Some(Flags(["create", "directory", "exclusive", "truncate"])),
    Some(DefValType(U64)),
    Some(Option(TypeIdx(7))),
    Some(Record([{ label: "type", ty: TypeIdx(10) }, { label: "link-count", ty: TypeIdx(14) }, { label: "size", ty: TypeIdx(8) }, { label: "data-access-timestamp", ty: TypeIdx(15) }, { label: "data-modification-timestamp", ty: TypeIdx(15) }, { label: "status-change-timestamp", ty: TypeIdx(15) }])),
    Some(Variant([{ label: "no-change", ty: None, refines: None }, { label: "now", ty: None, refines: None }, { label: "timestamp", ty: Some(TypeIdx(7)), refines: None }])),
    Some(Record([{ label: "type", ty: TypeIdx(10) }, { label: "name", ty: Prim(String) }])),
    Some(Variant([{ label: "access", ty: None, refines: None }, { label: "already", ty: None, refines: None }, { label: "bad-descriptor", ty: None, refines: None }, { label: "busy", ty: None, refines: None }, { label: "deadlock", ty: None, refines: None }, { label: "quota", ty: None, refines: None }, { label: "exist", ty: None, refines: None }, { label: "file-too-large", ty: None, refines: None }, { label: "illegal-byte-sequence", ty: None, refines: None }, { label: "in-progress", ty: None, refines: None }, { label: "interrupted", ty: None, refines: None }, { label: "invalid", ty: None, refines: None }, { label: "io", ty: None, refines: None }, { label: "is-directory", ty: None, refines: None }, { label: "loop", ty: None, refines: None }, { label: "too-many-links", ty: None, refines: None }, { label: "message-size", ty: None, refines: None }, { label: "name-too-long", ty: None, refines: None }, { label: "no-device", ty: None, refines: None }, { label: "no-entry", ty: None, refines: None }, { label: "no-lock", ty: None, refines: None }, { label: "insufficient-memory", ty: None, refines: None }, { label: "insufficient-space", ty: None, refines: None }, { label: "not-directory", ty: None, refines: None }, { label: "not-empty", ty: None, refines: None }, { label: "not-recoverable", ty: None, refines: None }, { label: "unsupported", ty: None, refines: None }, { label: "no-tty", ty: None, refines: None }, { label: "no-such-device", ty: None, refines: None }, { label: "overflow", ty: None, refines: None }, { label: "not-permitted", ty: None, refines: None }, { label: "pipe", ty: None, refines: None }, { label: "read-only", ty: None, refines: None }, { label: "invalid-seek", ty: None, refines: None }, { label: "text-file-busy", ty: None, refines: None }, { label: "cross-device", ty: None, refines: None }, { label: "other", ty: Some(TypeIdx(9)), refines: None }])),
    Some(Enum(["normal", "sequential", "random", "will-need", "dont-need", "no-reuse"])),
    Some(Record([{ label: "lower", ty: Prim(U64) }, { label: "upper", ty: Prim(U64) }])),
    resolve_resource("wasi:filesystem@0.3.0/types.descriptor"),
    Some(Borrow(22)),
    Some(Stream(Some(Prim(U8)))),
    Some(Result(None, Some(TypeIdx(19)))),
    Some(Future(Some(TypeIdx(25)))),
    Some(Tuple([TypeIdx(24), TypeIdx(26)])),
    Some(Result(Some(TypeIdx(11)), Some(TypeIdx(19)))),
    Some(Result(Some(TypeIdx(10)), Some(TypeIdx(19)))),
    Some(Stream(Some(TypeIdx(18)))),
    Some(Tuple([TypeIdx(30), TypeIdx(26)])),
    Some(Result(Some(TypeIdx(16)), Some(TypeIdx(19)))),
    Some(Own(22)),
    Some(Result(Some(TypeIdx(33)), Some(TypeIdx(19)))),
    Some(Result(Some(Prim(String)), Some(TypeIdx(19)))),
    Some(Result(Some(TypeIdx(21)), Some(TypeIdx(19)))),
    resolve_resource("wasi:filesystem@0.3.0/types.descriptor"),
    Some(Own(37)),
    Some(Tuple([TypeIdx(38), Prim(String)])),
    Some(List(TypeIdx(39))),
    Some(DefValType(U64)),
    Some(Option(Prim(String))),
    Some(Variant([{ label: "access-denied", ty: None, refines: None }, { label: "not-supported", ty: None, refines: None }, { label: "invalid-argument", ty: None, refines: None }, { label: "out-of-memory", ty: None, refines: None }, { label: "timeout", ty: None, refines: None }, { label: "invalid-state", ty: None, refines: None }, { label: "address-not-bindable", ty: None, refines: None }, { label: "address-in-use", ty: None, refines: None }, { label: "remote-unreachable", ty: None, refines: None }, { label: "connection-refused", ty: None, refines: None }, { label: "connection-broken", ty: None, refines: None }, { label: "connection-reset", ty: None, refines: None }, { label: "connection-aborted", ty: None, refines: None }, { label: "datagram-too-large", ty: None, refines: None }, { label: "other", ty: Some(TypeIdx(42)), refines: None }])),
    Some(Enum(["ipv4", "ipv6"])),
    Some(Tuple([Prim(U8), Prim(U8), Prim(U8), Prim(U8)])),
    Some(Tuple([Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16)])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(45)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(46)), refines: None }])),
    Some(Record([{ label: "port", ty: Prim(U16) }, { label: "address", ty: TypeIdx(45) }])),
    Some(Record([{ label: "port", ty: Prim(U16) }, { label: "flow-info", ty: Prim(U32) }, { label: "address", ty: TypeIdx(46) }, { label: "scope-id", ty: Prim(U32) }])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(48)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(49)), refines: None }])),
    resolve_resource("wasi:sockets@0.3.0/types.tcp-socket"),
    resolve_resource("wasi:sockets@0.3.0/types.udp-socket"),
    Some(Own(51)),
    Some(Result(Some(TypeIdx(53)), Some(TypeIdx(43)))),
    Some(Borrow(51)),
    Some(Result(None, Some(TypeIdx(43)))),
    Some(Stream(Some(TypeIdx(53)))),
    Some(Result(Some(TypeIdx(57)), Some(TypeIdx(43)))),
    Some(Stream(Some(Prim(U8)))),
    Some(Future(Some(TypeIdx(56)))),
    Some(Tuple([TypeIdx(59), TypeIdx(60)])),
    Some(Result(Some(TypeIdx(50)), Some(TypeIdx(43)))),
    Some(Result(Some(Prim(Bool)), Some(TypeIdx(43)))),
    Some(Result(Some(TypeIdx(41)), Some(TypeIdx(43)))),
    Some(Result(Some(Prim(U32)), Some(TypeIdx(43)))),
    Some(Result(Some(Prim(U8)), Some(TypeIdx(43)))),
    Some(Result(Some(Prim(U64)), Some(TypeIdx(43)))),
    Some(Own(52)),
    Some(Result(Some(TypeIdx(68)), Some(TypeIdx(43)))),
    Some(Borrow(52)),
    Some(List(Prim(U8))),
    Some(Option(TypeIdx(50))),
    Some(Tuple([TypeIdx(71), TypeIdx(50)])),
    Some(Result(Some(TypeIdx(73)), Some(TypeIdx(43)))),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(45)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(46)), refines: None }])),
    Some(Variant([{ label: "access-denied", ty: None, refines: None }, { label: "invalid-argument", ty: None, refines: None }, { label: "name-unresolvable", ty: None, refines: None }, { label: "temporary-resolver-failure", ty: None, refines: None }, { label: "permanent-resolver-failure", ty: None, refines: None }, { label: "other", ty: Some(TypeIdx(42)), refines: None }])),
    Some(List(TypeIdx(75))),
    Some(Result(Some(TypeIdx(77)), Some(TypeIdx(76)))),
    Some(Tuple([Prim(U64), Prim(U64)])),
    Some(List(Prim(U8))),
    Some(Tuple([Prim(String), Prim(String)])),
    Some(List(TypeIdx(81))),
    Some(List(Prim(String))),
    Some(Option(Prim(String))),
    Some(Result(None, None)),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Stream(Some(Prim(U8)))),
    Some(Result(None, Some(TypeIdx(87)))),
    Some(Future(Some(TypeIdx(89)))),
    Some(Tuple([TypeIdx(88), TypeIdx(90)])),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Result(None, Some(TypeIdx(92)))),
    Some(Future(Some(TypeIdx(93)))),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Result(None, Some(TypeIdx(95)))),
    Some(Future(Some(TypeIdx(96)))),
    resolve_resource("wasi:cli@0.3.0/terminal-input.terminal-input"),
    resolve_resource("wasi:cli@0.3.0/terminal-output.terminal-output"),
    resolve_resource("wasi:cli@0.3.0/terminal-input.terminal-input"),
    Some(Own(100)),
    Some(Option(TypeIdx(101))),
    resolve_resource("wasi:cli@0.3.0/terminal-output.terminal-output"),
    Some(Own(103)),
    Some(Option(TypeIdx(104))),
    resolve_resource("wasi:cli@0.3.0/terminal-output.terminal-output"),
    Some(Own(106)),
    Some(Option(TypeIdx(107))),
  ]
}

///|
fn wasi_preview3_func_type(
  interface : String,
  function : String,
) -> @component.FuncType? {
  match "\{interface}#\{function}" {
    "wasi:clocks@0.3.0/monotonic-clock#now" => Some({ is_async: false, params: [], result: Some(TypeIdx(2)) })
    "wasi:clocks@0.3.0/monotonic-clock#get-resolution" => Some({ is_async: false, params: [], result: Some(TypeIdx(1)) })
    "wasi:clocks@0.3.0/monotonic-clock#wait-until" => Some({ is_async: true, params: [{ label: "when", ty: TypeIdx(2) }], result: None })
    "wasi:clocks@0.3.0/monotonic-clock#wait-for" => Some({ is_async: true, params: [{ label: "how-long", ty: TypeIdx(1) }], result: None })
    "wasi:clocks@0.3.0/system-clock#now" => Some({ is_async: false, params: [], result: Some(TypeIdx(4)) })
    "wasi:clocks@0.3.0/system-clock#get-resolution" => Some({ is_async: false, params: [], result: Some(TypeIdx(3)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.read-via-stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(23) }, { label: "offset", ty: TypeIdx(8) }], result: Some(TypeIdx(27)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.write-via-stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(23) }, { label: "data", ty: TypeIdx(24) }, { label: "offset", ty: TypeIdx(8) }], result: Some(TypeIdx(26)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.append-via-stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(23) }, { label: "data", ty: TypeIdx(24) }], result: Some(TypeIdx(26)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.advise" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "offset", ty: TypeIdx(8) }, { label: "length", ty: TypeIdx(8) }, { label: "advice", ty: TypeIdx(20) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.sync-data" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.get-flags" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }], result: Some(TypeIdx(28)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.get-type" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }], result: Some(TypeIdx(29)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.set-size" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "size", ty: TypeIdx(8) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.set-times" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "data-access-timestamp", ty: TypeIdx(17) }, { label: "data-modification-timestamp", ty: TypeIdx(17) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.read-directory" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(23) }], result: Some(TypeIdx(31)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.sync" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.create-directory-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.stat" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }], result: Some(TypeIdx(32)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.stat-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path-flags", ty: TypeIdx(12) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(32)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.set-times-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path-flags", ty: TypeIdx(12) }, { label: "path", ty: Prim(String) }, { label: "data-access-timestamp", ty: TypeIdx(17) }, { label: "data-modification-timestamp", ty: TypeIdx(17) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.link-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "old-path-flags", ty: TypeIdx(12) }, { label: "old-path", ty: Prim(String) }, { label: "new-descriptor", ty: TypeIdx(23) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.open-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path-flags", ty: TypeIdx(12) }, { label: "path", ty: Prim(String) }, { label: "open-flags", ty: TypeIdx(13) }, { label: "flags", ty: TypeIdx(11) }], result: Some(TypeIdx(34)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.readlink-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(35)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.remove-directory-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.rename-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "old-path", ty: Prim(String) }, { label: "new-descriptor", ty: TypeIdx(23) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.symlink-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "old-path", ty: Prim(String) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.unlink-file-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.is-same-object" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "other", ty: TypeIdx(23) }], result: Some(Prim(Bool)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.metadata-hash" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }], result: Some(TypeIdx(36)) })
    "wasi:filesystem@0.3.0/types#[method]descriptor.metadata-hash-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(23) }, { label: "path-flags", ty: TypeIdx(12) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(36)) })
    "wasi:filesystem@0.3.0/preopens#get-directories" => Some({ is_async: false, params: [], result: Some(TypeIdx(40)) })
    "wasi:sockets@0.3.0/types#[static]tcp-socket.create" => Some({ is_async: false, params: [{ label: "address-family", ty: TypeIdx(44) }], result: Some(TypeIdx(54)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "local-address", ty: TypeIdx(50) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.connect" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(55) }, { label: "remote-address", ty: TypeIdx(50) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.listen" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(58)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.send" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "data", ty: TypeIdx(59) }], result: Some(TypeIdx(60)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.receive" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(61)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-local-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-remote-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-is-listening" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(Prim(Bool)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-address-family" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(44)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-listen-backlog-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-keep-alive-enabled" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(63)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-keep-alive-enabled" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: Prim(Bool) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-keep-alive-idle-time" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(64)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-keep-alive-idle-time" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: TypeIdx(41) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-keep-alive-interval" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(64)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-keep-alive-interval" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: TypeIdx(41) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-keep-alive-count" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(65)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-keep-alive-count" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: Prim(U32) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(66)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: Prim(U8) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(67)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.get-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }], result: Some(TypeIdx(67)) })
    "wasi:sockets@0.3.0/types#[method]tcp-socket.set-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(55) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[static]udp-socket.create" => Some({ is_async: false, params: [{ label: "address-family", ty: TypeIdx(44) }], result: Some(TypeIdx(69)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }, { label: "local-address", ty: TypeIdx(50) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.connect" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }, { label: "remote-address", ty: TypeIdx(50) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.disconnect" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.send" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(70) }, { label: "data", ty: TypeIdx(71) }, { label: "remote-address", ty: TypeIdx(72) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.receive" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(74)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.get-local-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.get-remote-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.get-address-family" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(44)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.get-unicast-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(66)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.set-unicast-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }, { label: "value", ty: Prim(U8) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.get-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(67)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.set-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.get-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }], result: Some(TypeIdx(67)) })
    "wasi:sockets@0.3.0/types#[method]udp-socket.set-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(70) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0/ip-name-lookup#resolve-addresses" => Some({ is_async: true, params: [{ label: "name", ty: Prim(String) }], result: Some(TypeIdx(78)) })
    "wasi:random@0.3.0/insecure-seed#get-insecure-seed" => Some({ is_async: false, params: [], result: Some(TypeIdx(79)) })
    "wasi:random@0.3.0/insecure#get-insecure-random-bytes" => Some({ is_async: false, params: [{ label: "max-len", ty: Prim(U64) }], result: Some(TypeIdx(80)) })
    "wasi:random@0.3.0/insecure#get-insecure-random-u64" => Some({ is_async: false, params: [], result: Some(Prim(U64)) })
    "wasi:random@0.3.0/random#get-random-bytes" => Some({ is_async: false, params: [{ label: "max-len", ty: Prim(U64) }], result: Some(TypeIdx(80)) })
    "wasi:random@0.3.0/random#get-random-u64" => Some({ is_async: false, params: [], result: Some(Prim(U64)) })
    "wasi:cli@0.3.0/environment#get-environment" => Some({ is_async: false, params: [], result: Some(TypeIdx(82)) })
    "wasi:cli@0.3.0/environment#get-arguments" => Some({ is_async: false, params: [], result: Some(TypeIdx(83)) })
    "wasi:cli@0.3.0/environment#get-initial-cwd" => Some({ is_async: false, params: [], result: Some(TypeIdx(84)) })
    "wasi:cli@0.3.0/exit#exit" => Some({ is_async: false, params: [{ label: "status", ty: TypeIdx(85) }], result: None })
    "wasi:cli@0.3.0/exit#exit-with-code" => Some({ is_async: false, params: [{ label: "status-code", ty: Prim(U8) }], result: None })
    "wasi:cli@0.3.0/run#run" => Some({ is_async: true, params: [], result: Some(TypeIdx(85)) })
    "wasi:cli@0.3.0/stdin#read-via-stream" => Some({ is_async: false, params: [], result: Some(TypeIdx(91)) })
    "wasi:cli@0.3.0/stdout#write-via-stream" => Some({ is_async: false, params: [{ label: "data", ty: TypeIdx(88) }], result: Some(TypeIdx(94)) })
    "wasi:cli@0.3.0/stderr#write-via-stream" => Some({ is_async: false, params: [{ label: "data", ty: TypeIdx(88) }], result: Some(TypeIdx(97)) })
    "wasi:cli@0.3.0/terminal-stdin#get-terminal-stdin" => Some({ is_async: false, params: [], result: Some(TypeIdx(102)) })
    "wasi:cli@0.3.0/terminal-stdout#get-terminal-stdout" => Some({ is_async: false, params: [], result: Some(TypeIdx(105)) })
    "wasi:cli@0.3.0/terminal-stderr#get-terminal-stderr" => Some({ is_async: false, params: [], result: Some(TypeIdx(108)) })
    _ => None
  }
}

///|
fn wasi_preview3_exported_types(
  interface : String,
) -> Array[(String, Int)] {
  match interface {
    "wasi:clocks@0.3.0/types" => [("duration", 0)]
    "wasi:clocks@0.3.0/monotonic-clock" => [("duration", 1), ("mark", 2)]
    "wasi:clocks@0.3.0/system-clock" => [("duration", 3), ("instant", 4)]
    "wasi:filesystem@0.3.0/types" => [("instant", 7), ("filesize", 8), ("descriptor-type", 10), ("descriptor-flags", 11), ("path-flags", 12), ("open-flags", 13), ("link-count", 14), ("descriptor-stat", 16), ("new-timestamp", 17), ("directory-entry", 18), ("error-code", 19), ("advice", 20), ("metadata-hash-value", 21), ("descriptor", 22)]
    "wasi:filesystem@0.3.0/preopens" => [("descriptor", 37)]
    "wasi:sockets@0.3.0/types" => [("duration", 41), ("error-code", 43), ("ip-address-family", 44), ("ipv4-address", 45), ("ipv6-address", 46), ("ip-address", 47), ("ipv4-socket-address", 48), ("ipv6-socket-address", 49), ("ip-socket-address", 50), ("tcp-socket", 51), ("udp-socket", 52)]
    "wasi:sockets@0.3.0/ip-name-lookup" => [("ip-address", 75), ("error-code", 76)]
    "wasi:random@0.3.0/insecure-seed" => []
    "wasi:random@0.3.0/insecure" => []
    "wasi:random@0.3.0/random" => []
    "wasi:cli@0.3.0/environment" => []
    "wasi:cli@0.3.0/exit" => []
    "wasi:cli@0.3.0/run" => []
    "wasi:cli@0.3.0/types" => [("error-code", 86)]
    "wasi:cli@0.3.0/stdin" => [("error-code", 87)]
    "wasi:cli@0.3.0/stdout" => [("error-code", 92)]
    "wasi:cli@0.3.0/stderr" => [("error-code", 95)]
    "wasi:cli@0.3.0/terminal-input" => [("terminal-input", 98)]
    "wasi:cli@0.3.0/terminal-output" => [("terminal-output", 99)]
    "wasi:cli@0.3.0/terminal-stdin" => [("terminal-input", 100)]
    "wasi:cli@0.3.0/terminal-stdout" => [("terminal-output", 103)]
    "wasi:cli@0.3.0/terminal-stderr" => [("terminal-output", 106)]
    _ => []
  }
}
