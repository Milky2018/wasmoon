///|
test "safepoint descriptors reject malformed maps before publication" {
  let context = @jit_ffi.JITContext::new(1)
  let retained = context_with_owned_gc_payloads()
  let valid = b"\x02\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00"
  assert_true(context.bind_gc_safepoints(0, valid, [4]))
  let malformed : Array[(Bytes, FixedArray[Int32])] = [
    (b"\x01", [4]),
    (valid, []),
    (valid[:16].to_owned(), [4]),
    (valid + b"\x00", [4]),
    (b"\x02\x00\x00\x00\xff\xff\xff\xff", [4]),
    // A record may not consume the space reserved for subsequent headers.
    (
      b"\x02\x00\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
      [4, 8],
    ),
    (
      b"\x02\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\xff\xff\xff\xff",
      [4],
    ),
    (
      b"\x02\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00",
      [4],
    ),
  ]
  for (blob, offsets) in malformed {
    assert_false(context.bind_gc_safepoints(0, blob, offsets))
    assert_false(retained.bind_gc_safepoints(0, blob, offsets))
    assert_eq(@native_test_support.context_gc_payload_valid(retained), 1)
    let rejected = try {
      @jit_ffi.PreparedSafepoints::new([blob], [offsets]) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    // Failed admission must leave a valid context reusable.
    assert_true(context.bind_gc_safepoints(0, valid, [4]))
  }
}
