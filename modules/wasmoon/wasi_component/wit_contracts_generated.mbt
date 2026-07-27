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
let wasi_preview3_wit_sha256 : String = "8948c1651d7fc84a921565845ff9975bcac4508c54f16bb735f476ee53503f33"

///|
fn wasi_preview3_resource_names() -> Array[String] {
  [
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-input.terminal-input",
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-output.terminal-output",
    "wasi:filesystem@0.3.0-rc-2025-09-16/types.descriptor",
    "wasi:sockets@0.3.0-rc-2025-09-16/types.tcp-socket",
    "wasi:sockets@0.3.0-rc-2025-09-16/types.udp-socket",
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
    Some(Record([{ label: "seconds", ty: Prim(U64) }, { label: "nanoseconds", ty: Prim(U32) }])),
    Some(Record([{ label: "seconds", ty: Prim(U64) }, { label: "nanoseconds", ty: Prim(U32) }])),
    Some(DefValType(U64)),
    Some(Enum(["unknown", "block-device", "character-device", "directory", "fifo", "symbolic-link", "regular-file", "socket"])),
    Some(Flags(["read", "write", "file-integrity-sync", "data-integrity-sync", "requested-write-sync", "mutate-directory"])),
    Some(Flags(["symlink-follow"])),
    Some(Flags(["create", "directory", "exclusive", "truncate"])),
    Some(DefValType(U64)),
    Some(Option(TypeIdx(4))),
    Some(Record([{ label: "type", ty: TypeIdx(6) }, { label: "link-count", ty: TypeIdx(10) }, { label: "size", ty: TypeIdx(5) }, { label: "data-access-timestamp", ty: TypeIdx(11) }, { label: "data-modification-timestamp", ty: TypeIdx(11) }, { label: "status-change-timestamp", ty: TypeIdx(11) }])),
    Some(Variant([{ label: "no-change", ty: None, refines: None }, { label: "now", ty: None, refines: None }, { label: "timestamp", ty: Some(TypeIdx(4)), refines: None }])),
    Some(Record([{ label: "type", ty: TypeIdx(6) }, { label: "name", ty: Prim(String) }])),
    Some(Enum(["access", "already", "bad-descriptor", "busy", "deadlock", "quota", "exist", "file-too-large", "illegal-byte-sequence", "in-progress", "interrupted", "invalid", "io", "is-directory", "loop", "too-many-links", "message-size", "name-too-long", "no-device", "no-entry", "no-lock", "insufficient-memory", "insufficient-space", "not-directory", "not-empty", "not-recoverable", "unsupported", "no-tty", "no-such-device", "overflow", "not-permitted", "pipe", "read-only", "invalid-seek", "text-file-busy", "cross-device"])),
    Some(Enum(["normal", "sequential", "random", "will-need", "dont-need", "no-reuse"])),
    Some(Record([{ label: "lower", ty: Prim(U64) }, { label: "upper", ty: Prim(U64) }])),
    resolve_resource("wasi:filesystem@0.3.0-rc-2025-09-16/types.descriptor"),
    Some(Borrow(18)),
    Some(Stream(Some(Prim(U8)))),
    Some(Result(None, Some(TypeIdx(15)))),
    Some(Future(Some(TypeIdx(21)))),
    Some(Tuple([TypeIdx(20), TypeIdx(22)])),
    Some(Result(Some(TypeIdx(7)), Some(TypeIdx(15)))),
    Some(Result(Some(TypeIdx(6)), Some(TypeIdx(15)))),
    Some(Stream(Some(TypeIdx(14)))),
    Some(Tuple([TypeIdx(26), TypeIdx(22)])),
    Some(Result(Some(TypeIdx(12)), Some(TypeIdx(15)))),
    Some(Own(18)),
    Some(Result(Some(TypeIdx(29)), Some(TypeIdx(15)))),
    Some(Result(Some(Prim(String)), Some(TypeIdx(15)))),
    Some(Result(Some(TypeIdx(17)), Some(TypeIdx(15)))),
    resolve_resource("wasi:filesystem@0.3.0-rc-2025-09-16/types.descriptor"),
    Some(Own(33)),
    Some(Tuple([TypeIdx(34), Prim(String)])),
    Some(List(TypeIdx(35))),
    Some(DefValType(U64)),
    Some(Enum(["unknown", "access-denied", "not-supported", "invalid-argument", "out-of-memory", "timeout", "invalid-state", "address-not-bindable", "address-in-use", "remote-unreachable", "connection-refused", "connection-reset", "connection-aborted", "datagram-too-large"])),
    Some(Enum(["ipv4", "ipv6"])),
    Some(Tuple([Prim(U8), Prim(U8), Prim(U8), Prim(U8)])),
    Some(Tuple([Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16), Prim(U16)])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(40)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(41)), refines: None }])),
    Some(Record([{ label: "port", ty: Prim(U16) }, { label: "address", ty: TypeIdx(40) }])),
    Some(Record([{ label: "port", ty: Prim(U16) }, { label: "flow-info", ty: Prim(U32) }, { label: "address", ty: TypeIdx(41) }, { label: "scope-id", ty: Prim(U32) }])),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(43)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(44)), refines: None }])),
    resolve_resource("wasi:sockets@0.3.0-rc-2025-09-16/types.tcp-socket"),
    resolve_resource("wasi:sockets@0.3.0-rc-2025-09-16/types.udp-socket"),
    Some(Own(46)),
    Some(Result(Some(TypeIdx(48)), Some(TypeIdx(38)))),
    Some(Borrow(46)),
    Some(Result(None, Some(TypeIdx(38)))),
    Some(Stream(Some(TypeIdx(48)))),
    Some(Result(Some(TypeIdx(52)), Some(TypeIdx(38)))),
    Some(Stream(Some(Prim(U8)))),
    Some(Future(Some(TypeIdx(51)))),
    Some(Tuple([TypeIdx(54), TypeIdx(55)])),
    Some(Result(Some(TypeIdx(45)), Some(TypeIdx(38)))),
    Some(Result(Some(Prim(Bool)), Some(TypeIdx(38)))),
    Some(Result(Some(TypeIdx(37)), Some(TypeIdx(38)))),
    Some(Result(Some(Prim(U32)), Some(TypeIdx(38)))),
    Some(Result(Some(Prim(U8)), Some(TypeIdx(38)))),
    Some(Result(Some(Prim(U64)), Some(TypeIdx(38)))),
    Some(Own(47)),
    Some(Result(Some(TypeIdx(63)), Some(TypeIdx(38)))),
    Some(Borrow(47)),
    Some(List(Prim(U8))),
    Some(Option(TypeIdx(45))),
    Some(Tuple([TypeIdx(66), TypeIdx(45)])),
    Some(Result(Some(TypeIdx(68)), Some(TypeIdx(38)))),
    Some(Variant([{ label: "ipv4", ty: Some(TypeIdx(40)), refines: None }, { label: "ipv6", ty: Some(TypeIdx(41)), refines: None }])),
    Some(Enum(["unknown", "access-denied", "invalid-argument", "name-unresolvable", "temporary-resolver-failure", "permanent-resolver-failure"])),
    Some(List(TypeIdx(70))),
    Some(Result(Some(TypeIdx(72)), Some(TypeIdx(71)))),
    Some(Tuple([Prim(U64), Prim(U64)])),
    Some(List(Prim(U8))),
    Some(Tuple([Prim(String), Prim(String)])),
    Some(List(TypeIdx(76))),
    Some(List(Prim(String))),
    Some(Option(Prim(String))),
    Some(Result(None, None)),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Stream(Some(Prim(U8)))),
    Some(Result(None, Some(TypeIdx(82)))),
    Some(Future(Some(TypeIdx(84)))),
    Some(Tuple([TypeIdx(83), TypeIdx(85)])),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Result(None, Some(TypeIdx(87)))),
    Some(Enum(["io", "illegal-byte-sequence", "pipe"])),
    Some(Result(None, Some(TypeIdx(89)))),
    resolve_resource("wasi:cli@0.3.0-rc-2025-09-16/terminal-input.terminal-input"),
    resolve_resource("wasi:cli@0.3.0-rc-2025-09-16/terminal-output.terminal-output"),
    resolve_resource("wasi:cli@0.3.0-rc-2025-09-16/terminal-input.terminal-input"),
    Some(Own(93)),
    Some(Option(TypeIdx(94))),
    resolve_resource("wasi:cli@0.3.0-rc-2025-09-16/terminal-output.terminal-output"),
    Some(Own(96)),
    Some(Option(TypeIdx(97))),
    resolve_resource("wasi:cli@0.3.0-rc-2025-09-16/terminal-output.terminal-output"),
    Some(Own(99)),
    Some(Option(TypeIdx(100))),
  ]
}

///|
fn wasi_preview3_func_type(
  interface : String,
  function : String,
) -> @component.FuncType? {
  match "\{interface}#\{function}" {
    "wasi:clocks@0.3.0-rc-2025-09-16/monotonic-clock#now" => Some({ is_async: false, params: [], result: Some(TypeIdx(2)) })
    "wasi:clocks@0.3.0-rc-2025-09-16/monotonic-clock#get-resolution" => Some({ is_async: false, params: [], result: Some(TypeIdx(1)) })
    "wasi:clocks@0.3.0-rc-2025-09-16/monotonic-clock#wait-until" => Some({ is_async: true, params: [{ label: "when", ty: TypeIdx(2) }], result: None })
    "wasi:clocks@0.3.0-rc-2025-09-16/monotonic-clock#wait-for" => Some({ is_async: true, params: [{ label: "how-long", ty: TypeIdx(1) }], result: None })
    "wasi:clocks@0.3.0-rc-2025-09-16/wall-clock#now" => Some({ is_async: false, params: [], result: Some(TypeIdx(3)) })
    "wasi:clocks@0.3.0-rc-2025-09-16/wall-clock#get-resolution" => Some({ is_async: false, params: [], result: Some(TypeIdx(3)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.read-via-stream" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(19) }, { label: "offset", ty: TypeIdx(5) }], result: Some(TypeIdx(23)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.write-via-stream" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "data", ty: TypeIdx(20) }, { label: "offset", ty: TypeIdx(5) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.append-via-stream" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "data", ty: TypeIdx(20) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.advise" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "offset", ty: TypeIdx(5) }, { label: "length", ty: TypeIdx(5) }, { label: "advice", ty: TypeIdx(16) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.sync-data" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.get-flags" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }], result: Some(TypeIdx(24)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.get-type" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }], result: Some(TypeIdx(25)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.set-size" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "size", ty: TypeIdx(5) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.set-times" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "data-access-timestamp", ty: TypeIdx(13) }, { label: "data-modification-timestamp", ty: TypeIdx(13) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.read-directory" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }], result: Some(TypeIdx(27)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.sync" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.create-directory-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.stat" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }], result: Some(TypeIdx(28)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.stat-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path-flags", ty: TypeIdx(8) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(28)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.set-times-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path-flags", ty: TypeIdx(8) }, { label: "path", ty: Prim(String) }, { label: "data-access-timestamp", ty: TypeIdx(13) }, { label: "data-modification-timestamp", ty: TypeIdx(13) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.link-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "old-path-flags", ty: TypeIdx(8) }, { label: "old-path", ty: Prim(String) }, { label: "new-descriptor", ty: TypeIdx(19) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.open-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path-flags", ty: TypeIdx(8) }, { label: "path", ty: Prim(String) }, { label: "open-flags", ty: TypeIdx(9) }, { label: "flags", ty: TypeIdx(7) }], result: Some(TypeIdx(30)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.readlink-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(31)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.remove-directory-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.rename-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "old-path", ty: Prim(String) }, { label: "new-descriptor", ty: TypeIdx(19) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.symlink-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "old-path", ty: Prim(String) }, { label: "new-path", ty: Prim(String) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.unlink-file-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(21)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.is-same-object" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "other", ty: TypeIdx(19) }], result: Some(Prim(Bool)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.metadata-hash" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }], result: Some(TypeIdx(32)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/types#[method]descriptor.metadata-hash-at" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(19) }, { label: "path-flags", ty: TypeIdx(8) }, { label: "path", ty: Prim(String) }], result: Some(TypeIdx(32)) })
    "wasi:filesystem@0.3.0-rc-2025-09-16/preopens#get-directories" => Some({ is_async: false, params: [], result: Some(TypeIdx(36)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[static]tcp-socket.create" => Some({ is_async: false, params: [{ label: "address-family", ty: TypeIdx(39) }], result: Some(TypeIdx(49)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "local-address", ty: TypeIdx(45) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.connect" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(50) }, { label: "remote-address", ty: TypeIdx(45) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.listen" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(53)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.send" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(50) }, { label: "data", ty: TypeIdx(54) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.receive" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(56)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-local-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(57)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-remote-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(57)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-is-listening" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(Prim(Bool)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-address-family" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(39)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-listen-backlog-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-keep-alive-enabled" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(58)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-keep-alive-enabled" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: Prim(Bool) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-keep-alive-idle-time" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(59)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-keep-alive-idle-time" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: TypeIdx(37) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-keep-alive-interval" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(59)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-keep-alive-interval" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: TypeIdx(37) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-keep-alive-count" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(60)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-keep-alive-count" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: Prim(U32) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(61)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: Prim(U8) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.get-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]tcp-socket.set-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(50) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[static]udp-socket.create" => Some({ is_async: false, params: [{ label: "address-family", ty: TypeIdx(39) }], result: Some(TypeIdx(64)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.bind" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }, { label: "local-address", ty: TypeIdx(45) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.connect" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }, { label: "remote-address", ty: TypeIdx(45) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.disconnect" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.send" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(65) }, { label: "data", ty: TypeIdx(66) }, { label: "remote-address", ty: TypeIdx(67) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.receive" => Some({ is_async: true, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(69)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.get-local-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(57)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.get-remote-address" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(57)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.get-address-family" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(39)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.get-unicast-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(61)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.set-unicast-hop-limit" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }, { label: "value", ty: Prim(U8) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.get-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.set-receive-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.get-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }], result: Some(TypeIdx(62)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/types#[method]udp-socket.set-send-buffer-size" => Some({ is_async: false, params: [{ label: "self", ty: TypeIdx(65) }, { label: "value", ty: Prim(U64) }], result: Some(TypeIdx(51)) })
    "wasi:sockets@0.3.0-rc-2025-09-16/ip-name-lookup#resolve-addresses" => Some({ is_async: true, params: [{ label: "name", ty: Prim(String) }], result: Some(TypeIdx(73)) })
    "wasi:random@0.3.0-rc-2025-09-16/insecure-seed#get-insecure-seed" => Some({ is_async: false, params: [], result: Some(TypeIdx(74)) })
    "wasi:random@0.3.0-rc-2025-09-16/insecure#get-insecure-random-bytes" => Some({ is_async: false, params: [{ label: "len", ty: Prim(U64) }], result: Some(TypeIdx(75)) })
    "wasi:random@0.3.0-rc-2025-09-16/insecure#get-insecure-random-u64" => Some({ is_async: false, params: [], result: Some(Prim(U64)) })
    "wasi:random@0.3.0-rc-2025-09-16/random#get-random-bytes" => Some({ is_async: false, params: [{ label: "len", ty: Prim(U64) }], result: Some(TypeIdx(75)) })
    "wasi:random@0.3.0-rc-2025-09-16/random#get-random-u64" => Some({ is_async: false, params: [], result: Some(Prim(U64)) })
    "wasi:cli@0.3.0-rc-2025-09-16/environment#get-environment" => Some({ is_async: false, params: [], result: Some(TypeIdx(77)) })
    "wasi:cli@0.3.0-rc-2025-09-16/environment#get-arguments" => Some({ is_async: false, params: [], result: Some(TypeIdx(78)) })
    "wasi:cli@0.3.0-rc-2025-09-16/environment#get-initial-cwd" => Some({ is_async: false, params: [], result: Some(TypeIdx(79)) })
    "wasi:cli@0.3.0-rc-2025-09-16/exit#exit" => Some({ is_async: false, params: [{ label: "status", ty: TypeIdx(80) }], result: None })
    "wasi:cli@0.3.0-rc-2025-09-16/run#run" => Some({ is_async: true, params: [], result: Some(TypeIdx(80)) })
    "wasi:cli@0.3.0-rc-2025-09-16/stdin#read-via-stream" => Some({ is_async: false, params: [], result: Some(TypeIdx(86)) })
    "wasi:cli@0.3.0-rc-2025-09-16/stdout#write-via-stream" => Some({ is_async: true, params: [{ label: "data", ty: TypeIdx(83) }], result: Some(TypeIdx(88)) })
    "wasi:cli@0.3.0-rc-2025-09-16/stderr#write-via-stream" => Some({ is_async: true, params: [{ label: "data", ty: TypeIdx(83) }], result: Some(TypeIdx(90)) })
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-stdin#get-terminal-stdin" => Some({ is_async: false, params: [], result: Some(TypeIdx(95)) })
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-stdout#get-terminal-stdout" => Some({ is_async: false, params: [], result: Some(TypeIdx(98)) })
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-stderr#get-terminal-stderr" => Some({ is_async: false, params: [], result: Some(TypeIdx(101)) })
    _ => None
  }
}

///|
fn wasi_preview3_exported_types(
  interface : String,
) -> Array[(String, Int)] {
  match interface {
    "wasi:clocks@0.3.0-rc-2025-09-16/types" => [("duration", 0)]
    "wasi:clocks@0.3.0-rc-2025-09-16/monotonic-clock" => [("duration", 1), ("instant", 2)]
    "wasi:clocks@0.3.0-rc-2025-09-16/wall-clock" => [("datetime", 3)]
    "wasi:filesystem@0.3.0-rc-2025-09-16/types" => [("datetime", 4), ("filesize", 5), ("descriptor-type", 6), ("descriptor-flags", 7), ("path-flags", 8), ("open-flags", 9), ("link-count", 10), ("descriptor-stat", 12), ("new-timestamp", 13), ("directory-entry", 14), ("error-code", 15), ("advice", 16), ("metadata-hash-value", 17), ("descriptor", 18)]
    "wasi:filesystem@0.3.0-rc-2025-09-16/preopens" => [("descriptor", 33)]
    "wasi:sockets@0.3.0-rc-2025-09-16/types" => [("duration", 37), ("error-code", 38), ("ip-address-family", 39), ("ipv4-address", 40), ("ipv6-address", 41), ("ip-address", 42), ("ipv4-socket-address", 43), ("ipv6-socket-address", 44), ("ip-socket-address", 45), ("tcp-socket", 46), ("udp-socket", 47)]
    "wasi:sockets@0.3.0-rc-2025-09-16/ip-name-lookup" => [("ip-address", 70), ("error-code", 71)]
    "wasi:random@0.3.0-rc-2025-09-16/insecure-seed" => []
    "wasi:random@0.3.0-rc-2025-09-16/insecure" => []
    "wasi:random@0.3.0-rc-2025-09-16/random" => []
    "wasi:cli@0.3.0-rc-2025-09-16/environment" => []
    "wasi:cli@0.3.0-rc-2025-09-16/exit" => []
    "wasi:cli@0.3.0-rc-2025-09-16/run" => []
    "wasi:cli@0.3.0-rc-2025-09-16/types" => [("error-code", 81)]
    "wasi:cli@0.3.0-rc-2025-09-16/stdin" => [("error-code", 82)]
    "wasi:cli@0.3.0-rc-2025-09-16/stdout" => [("error-code", 87)]
    "wasi:cli@0.3.0-rc-2025-09-16/stderr" => [("error-code", 89)]
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-input" => [("terminal-input", 91)]
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-output" => [("terminal-output", 92)]
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-stdin" => [("terminal-input", 93)]
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-stdout" => [("terminal-output", 96)]
    "wasi:cli@0.3.0-rc-2025-09-16/terminal-stderr" => [("terminal-output", 99)]
    _ => []
  }
}
