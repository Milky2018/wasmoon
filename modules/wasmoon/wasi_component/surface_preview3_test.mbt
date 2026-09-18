///|
// Inventory from the pinned preview3.contracts.json. This verifies registration,
// not the behavior of every operation.
test "Preview 3 command host registers every pinned WIT function and type" {
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder().build()
  defer ctx.close()
  defer linker.close()
  @wasi_component.install_command_world(linker, ctx)
  let expected : Array[(String, Array[String], Array[String])] = [
    ("wasi:clocks/types@0.3.0", [], ["duration"]),
    (
      "wasi:clocks/monotonic-clock@0.3.0",
      ["now", "get-resolution", "wait-until", "wait-for"],
      ["duration", "mark"],
    ),
    (
      "wasi:clocks/system-clock@0.3.0",
      ["now", "get-resolution"],
      ["duration", "instant"],
    ),
    (
      "wasi:filesystem/types@0.3.0",
      [
        "[method]descriptor.read-via-stream", "[method]descriptor.write-via-stream",
        "[method]descriptor.append-via-stream", "[method]descriptor.advise", "[method]descriptor.sync-data",
        "[method]descriptor.get-flags", "[method]descriptor.get-type", "[method]descriptor.set-size",
        "[method]descriptor.set-times", "[method]descriptor.read-directory", "[method]descriptor.sync",
        "[method]descriptor.create-directory-at", "[method]descriptor.stat", "[method]descriptor.stat-at",
        "[method]descriptor.set-times-at", "[method]descriptor.link-at", "[method]descriptor.open-at",
        "[method]descriptor.readlink-at", "[method]descriptor.remove-directory-at",
        "[method]descriptor.rename-at", "[method]descriptor.symlink-at", "[method]descriptor.unlink-file-at",
        "[method]descriptor.is-same-object", "[method]descriptor.metadata-hash",
        "[method]descriptor.metadata-hash-at",
      ],
      [
        "instant", "filesize", "descriptor-type", "descriptor-flags", "path-flags",
        "open-flags", "link-count", "descriptor-stat", "new-timestamp", "directory-entry",
        "error-code", "advice", "metadata-hash-value", "descriptor",
      ],
    ),
    ("wasi:filesystem/preopens@0.3.0", ["get-directories"], ["descriptor"]),
    (
      "wasi:sockets/types@0.3.0",
      [
        "[static]tcp-socket.create", "[method]tcp-socket.bind", "[method]tcp-socket.connect",
        "[method]tcp-socket.listen", "[method]tcp-socket.send", "[method]tcp-socket.receive",
        "[method]tcp-socket.get-local-address", "[method]tcp-socket.get-remote-address",
        "[method]tcp-socket.get-is-listening", "[method]tcp-socket.get-address-family",
        "[method]tcp-socket.set-listen-backlog-size", "[method]tcp-socket.get-keep-alive-enabled",
        "[method]tcp-socket.set-keep-alive-enabled", "[method]tcp-socket.get-keep-alive-idle-time",
        "[method]tcp-socket.set-keep-alive-idle-time", "[method]tcp-socket.get-keep-alive-interval",
        "[method]tcp-socket.set-keep-alive-interval", "[method]tcp-socket.get-keep-alive-count",
        "[method]tcp-socket.set-keep-alive-count", "[method]tcp-socket.get-hop-limit",
        "[method]tcp-socket.set-hop-limit", "[method]tcp-socket.get-receive-buffer-size",
        "[method]tcp-socket.set-receive-buffer-size", "[method]tcp-socket.get-send-buffer-size",
        "[method]tcp-socket.set-send-buffer-size", "[static]udp-socket.create", "[method]udp-socket.bind",
        "[method]udp-socket.connect", "[method]udp-socket.disconnect", "[method]udp-socket.send",
        "[method]udp-socket.receive", "[method]udp-socket.get-local-address", "[method]udp-socket.get-remote-address",
        "[method]udp-socket.get-address-family", "[method]udp-socket.get-unicast-hop-limit",
        "[method]udp-socket.set-unicast-hop-limit", "[method]udp-socket.get-receive-buffer-size",
        "[method]udp-socket.set-receive-buffer-size", "[method]udp-socket.get-send-buffer-size",
        "[method]udp-socket.set-send-buffer-size",
      ],
      [
        "duration", "error-code", "ip-address-family", "ipv4-address", "ipv6-address",
        "ip-address", "ipv4-socket-address", "ipv6-socket-address", "ip-socket-address",
        "tcp-socket", "udp-socket",
      ],
    ),
    (
      "wasi:sockets/ip-name-lookup@0.3.0",
      ["resolve-addresses"],
      ["ip-address", "error-code"],
    ),
    ("wasi:random/insecure-seed@0.3.0", ["get-insecure-seed"], []),
    (
      "wasi:random/insecure@0.3.0",
      ["get-insecure-random-bytes", "get-insecure-random-u64"],
      [],
    ),
    ("wasi:random/random@0.3.0", ["get-random-bytes", "get-random-u64"], []),
    (
      "wasi:cli/environment@0.3.0",
      ["get-environment", "get-arguments", "get-initial-cwd"],
      [],
    ),
    ("wasi:cli/exit@0.3.0", ["exit", "exit-with-code"], []),
    ("wasi:cli/types@0.3.0", [], ["error-code"]),
    ("wasi:cli/stdin@0.3.0", ["read-via-stream"], ["error-code"]),
    ("wasi:cli/stdout@0.3.0", ["write-via-stream"], ["error-code"]),
    ("wasi:cli/stderr@0.3.0", ["write-via-stream"], ["error-code"]),
    ("wasi:cli/terminal-input@0.3.0", [], ["terminal-input"]),
    ("wasi:cli/terminal-output@0.3.0", [], ["terminal-output"]),
    (
      "wasi:cli/terminal-stdin@0.3.0",
      ["get-terminal-stdin"],
      ["terminal-input"],
    ),
    (
      "wasi:cli/terminal-stdout@0.3.0",
      ["get-terminal-stdout"],
      ["terminal-output"],
    ),
    (
      "wasi:cli/terminal-stderr@0.3.0",
      ["get-terminal-stderr"],
      ["terminal-output"],
    ),
  ]
  let missing : Array[String] = []
  for (name, functions, types) in expected {
    // clocks/types is synthesized from its primitive type equality at linking.
    if name == "wasi:clocks/types@0.3.0" {
      continue
    }
    guard linker.get_import(name) is Some(Instance(instance)) else {
      missing.push("interface: \{name}")
      continue
    }
    for name in functions {
      guard instance.get_export(name) is Some(Func(_)) else {
        missing.push("function: \{name}")
        continue
      }
    }
    for name in types {
      guard instance.get_export(name) is Some(Type(_)) else {
        missing.push("type: \{name}")
        continue
      }
    }
  }
  assert_eq(missing, [])
}
