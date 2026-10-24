///|
test "binary instruction sources retain module offsets and nested subtree boundaries" {
  let bytes = make_wasm_module([
    [0x00, 0x04, 0x01, 0x78, 0x00, 0x00],
    [0x01, 0x04, 0x01, 0x60, 0x00, 0x00],
    [0x03, 0x02, 0x01, 0x00],
    // code: non-canonical zero locals; block { if { nop } else { nop } }; end.
    [
      0x0a, 0x0e, 0x01, 0x0c, 0x80, 0x00, 0x02, 0x40, 0x04, 0x40, 0x01, 0x05, 0x01,
      0x0b, 0x0b, 0x0b,
    ],
  ])
  let ordinary = @parser.parse_module(bytes)
  let (module_, sources) = @parser.parse_module_with_sources(bytes)
  assert_eq(module_.codes, ordinary.codes)
  assert_eq(sources.length(), 1)
  assert_eq(
    sources[0].map(source => (source.byte_offset, source.subtree_end)),
    [(30, 4), (32, 4), (34, 3), (36, 4)],
  )
  assert_true(
    @types.validate_instruction_sources(module_.codes[0].body, sources[0]),
  )
  assert_false(
    @types.validate_instruction_sources(module_.codes[0].body, sources[0][:3]),
  )
  let stale = sources[0].copy()
  stale[0] = { byte_offset: stale[0].byte_offset, subtree_end: 1, }
  assert_false(
    @types.validate_instruction_sources(module_.codes[0].body, stale),
  )
  stale[0] = sources[0][0]
  stale[1] = { byte_offset: stale[0].byte_offset, subtree_end: 4, }
  assert_false(
    @types.validate_instruction_sources(module_.codes[0].body, stale),
  )
}
