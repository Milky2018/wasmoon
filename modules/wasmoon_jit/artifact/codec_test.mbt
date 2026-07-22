///|
fn decode_result(
  bytes : Bytes,
  limits? : DecodeLimits = DecodeLimits::default(),
) -> Result[Artifact, ArtifactDecodeError] {
  Ok(decode(bytes, limits~)) catch {
    error => Err(error)
  }
}

///|
fn decode_error(
  bytes : Bytes,
  limits? : DecodeLimits = DecodeLimits::default(),
) -> ArtifactDecodeError {
  match decode_result(bytes, limits~) {
    Err(error) => error
    Ok(_) => abort("expected artifact decoding to fail")
  }
}

///|
fn copy_bytes(bytes : Bytes) -> Array[Byte] {
  let result : Array[Byte] = []
  for byte in bytes {
    result.push(byte)
  }
  result
}

///|
fn prefix(bytes : Bytes, length : Int) -> Bytes {
  let result : Array[Byte] = []
  for i in 0..<length {
    result.push(bytes[i])
  }
  Bytes::from_array(result)
}

///|
test "codec round-trips every artifact field" {
  let artifact = sample_artifact()
  let encoded = encode(artifact)
  let decoded = decode(encoded)
  assert_eq(decoded, artifact)
}

///|
test "decoder returns structured format errors" {
  let encoded = encode(sample_artifact())
  let bad_magic = copy_bytes(encoded)
  bad_magic[0] = b'x'
  let old_version = copy_bytes(encoded)
  old_version[4] = b'\x08'
  let unknown_architecture = copy_bytes(encoded)
  unknown_architecture[8] = b'\xFF'
  let excessive_feature_count = copy_bytes(encoded)
  for index in 12..<16 {
    excessive_feature_count[index] = b'\xFF'
  }
  let invalid_utf8 = copy_bytes(encoded)
  invalid_utf8[20] = b'\xFF'
  let trailing = copy_bytes(encoded)
  trailing.push(b'\x00')
  let artifact = sample_artifact()
  let function = artifact.functions[0]
  let invalid_entry : Artifact = {
    ..artifact,
    functions: [{ ..function, entry_offset: function.code.length() }],
  }
  debug_inspect(
    [
      decode_error(Bytes::from_array(bad_magic)),
      decode_error(Bytes::from_array(old_version)),
      decode_error(Bytes::from_array(unknown_architecture)),
      decode_error(Bytes::from_array(excessive_feature_count)),
      decode_error(Bytes::from_array(invalid_utf8)),
      decode_error(Bytes::from_array(trailing)),
      decode_error(encode(invalid_entry)),
    ],
    content=(
      #|[
      #|  BadMagic,
      #|  UnsupportedVersion(version=8),
      #|  InvalidTag(field="manifest.target.architecture", tag=255),
      #|  InvalidValue(
      #|    field="manifest.required_cpu_features.length",
      #|    message="unsigned 32-bit value exceeds the host Int range",
      #|  ),
      #|  InvalidUtf8(field="manifest.required_cpu_features.name"),
      #|  TrailingBytes(count=1),
      #|  InvalidValue(
      #|    field="function.entry_offset",
      #|    message="offset is outside code or violates target instruction alignment",
      #|  ),
      #|]
    ),
  )
}

///|
test "decoder enforces every variable-length resource class" {
  let encoded = encode(sample_artifact())
  let defaults = DecodeLimits::default()
  debug_inspect(
    [
      decode_error(encoded, limits={
        ..defaults,
        max_artifact_bytes: encoded.length() - 1,
      }),
      decode_error(encoded, limits={ ..defaults, max_cpu_features: 0 }),
      decode_error(encoded, limits={ ..defaults, max_string_bytes: 3 }),
      decode_error(encoded, limits={ ..defaults, max_imports: 0 }),
      decode_error(encoded, limits={ ..defaults, max_signature_values: 0 }),
      decode_error(encoded, limits={ ..defaults, max_functions: 0 }),
      decode_error(encoded, limits={
        ..defaults,
        max_code_bytes_per_function: 3,
      }),
      decode_error(encoded, limits={ ..defaults, max_total_code_bytes: 3 }),
      decode_error(encoded, limits={
        ..defaults,
        max_relocations_per_function: 0,
      }),
      decode_error(encoded, limits={ ..defaults, max_sources_per_function: 0 }),
      decode_error(encoded, limits={ ..defaults, max_traps_per_function: 0 }),
      decode_error(encoded, limits={
        ..defaults,
        max_safepoints_per_function: 0,
      }),
      decode_error(encoded, limits={ ..defaults, max_roots_per_safepoint: 0 }),
      decode_error(encoded, limits={
        ..defaults,
        max_unwind_directives_per_function: 0,
      }),
    ],
    content=(
      #|[
      #|  ArtifactTooLarge(size=425, limit=424),
      #|  LimitExceeded(
      #|    field="manifest.required_cpu_features.length",
      #|    count=1,
      #|    limit=0,
      #|  ),
      #|  LimitExceeded(
      #|    field="manifest.required_cpu_features.name.length",
      #|    count=4,
      #|    limit=3,
      #|  ),
      #|  LimitExceeded(field="artifact.imports.length", count=1, limit=0),
      #|  LimitExceeded(
      #|    field="import.signature.params.length",
      #|    count=1,
      #|    limit=0,
      #|  ),
      #|  LimitExceeded(field="artifact.functions.length", count=1, limit=0),
      #|  LimitExceeded(field="function.code.length", count=4, limit=3),
      #|  LimitExceeded(field="artifact.total_code_bytes", count=4, limit=3),
      #|  LimitExceeded(field="function.relocations.length", count=1, limit=0),
      #|  LimitExceeded(field="function.sources.length", count=1, limit=0),
      #|  LimitExceeded(field="function.traps.length", count=1, limit=0),
      #|  LimitExceeded(field="function.safepoints.length", count=1, limit=0),
      #|  LimitExceeded(
      #|    field="function.safepoint.roots.length",
      #|    count=1,
      #|    limit=0,
      #|  ),
      #|  LimitExceeded(field="function.unwind.length", count=1, limit=0),
      #|]
    ),
  )
}

///|
test "every proper encoded prefix is rejected as truncated" {
  let encoded = encode(sample_artifact())
  for length in 0..<encoded.length() {
    assert_true(decode_result(prefix(encoded, length)) is Err(_))
  }
}

///|
test "encoder rejects a non-SHA-256 digest width" {
  let artifact = sample_artifact()
  let invalid : Artifact = {
    ..artifact,
    manifest: {
      ..artifact.manifest,
      module_identity: {
        ..artifact.manifest.module_identity,
        source_digest: { bytes: b"short" },
      },
    },
  }
  let result : Result[Bytes, ArtifactEncodeError] = Ok(encode(invalid)) catch {
    error => Err(error)
  }
  debug_inspect(
    result,
    content=(
      #|Err(
      #|  InvalidArtifactField(
      #|    field="manifest.module_identity.source_digest",
      #|    message="expected exactly 32 SHA-256 bytes",
      #|  ),
      #|)
    ),
  )
}
