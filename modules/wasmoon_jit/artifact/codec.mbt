///|
pub suberror ArtifactEncodeError {
  InvalidArtifactField(field~ : String, message~ : String)
} derive(Eq, Debug)

///|
pub suberror ArtifactDecodeError {
  ArtifactTooLarge(size~ : Int, limit~ : Int)
  BadMagic
  UnsupportedVersion(version~ : Int)
  Truncated(field~ : String, offset~ : Int, needed~ : Int, remaining~ : Int)
  InvalidTag(field~ : String, tag~ : Int)
  InvalidValue(field~ : String, message~ : String)
  InvalidUtf8(field~ : String)
  LimitExceeded(field~ : String, count~ : Int, limit~ : Int)
  TrailingBytes(count~ : Int)
} derive(Eq, Debug)

///|
/// Resource limits applied before allocating variable-length artifact data.
pub(all) struct DecodeLimits {
  max_artifact_bytes : Int
  max_imports : Int
  max_functions : Int
  max_cpu_features : Int
  max_string_bytes : Int
  max_signature_values : Int
  max_code_bytes_per_function : Int
  max_total_code_bytes : Int
  max_relocations_per_function : Int
  max_sources_per_function : Int
  max_traps_per_function : Int
  max_safepoints_per_function : Int
  max_unwind_directives_per_function : Int
  max_roots_per_safepoint : Int
} derive(Eq, Debug)

///|
pub fn DecodeLimits::default() -> DecodeLimits {
  {
    max_artifact_bytes: 512 * 1024 * 1024,
    max_imports: 100_000,
    max_functions: 1_000_000,
    max_cpu_features: 256,
    max_string_bytes: 1024 * 1024,
    max_signature_values: 10_000,
    max_code_bytes_per_function: 128 * 1024 * 1024,
    max_total_code_bytes: 512 * 1024 * 1024,
    max_relocations_per_function: 1_000_000,
    max_sources_per_function: 1_000_000,
    max_traps_per_function: 1_000_000,
    max_safepoints_per_function: 1_000_000,
    max_unwind_directives_per_function: 1_000_000,
    max_roots_per_safepoint: 1_000_000,
  }
}

///|
priv struct ByteWriter {
  bytes : Array[Byte]
}

///|
fn ByteWriter::new() -> ByteWriter {
  { bytes: [] }
}

///|
fn ByteWriter::write_u8(self : ByteWriter, value : Int) -> Unit {
  self.bytes.push((value & 0xFF).to_byte())
}

///|
fn ByteWriter::write_u32(
  self : ByteWriter,
  value : Int,
  field : String,
) -> Unit raise ArtifactEncodeError {
  if value < 0 || value.to_int64() > 0xFFFF_FFFFL {
    raise InvalidArtifactField(
      field~,
      message="expected an unsigned 32-bit value",
    )
  }
  self.write_u8(value)
  self.write_u8(value >> 8)
  self.write_u8(value >> 16)
  self.write_u8(value >> 24)
}

///|
fn ByteWriter::write_i64(self : ByteWriter, value : Int64) -> Unit {
  let bits = value.reinterpret_as_uint64()
  for shift in 0..<8 {
    self.write_u8((bits >> (shift * 8)).to_int())
  }
}

///|
fn ByteWriter::write_bool(self : ByteWriter, value : Bool) -> Unit {
  self.write_u8(if value { 1 } else { 0 })
}

///|
fn ByteWriter::write_bytes(self : ByteWriter, value : Bytes) -> Unit {
  for byte in value {
    self.bytes.push(byte)
  }
}

///|
fn ByteWriter::write_byte_array(self : ByteWriter, value : Array[Byte]) -> Unit {
  for byte in value {
    self.bytes.push(byte)
  }
}

///|
fn ByteWriter::write_string(
  self : ByteWriter,
  value : String,
  field : String,
) -> Unit raise ArtifactEncodeError {
  let encoded = @utf8.encode(value)
  self.write_u32(encoded.length(), field)
  self.write_bytes(encoded)
}

///|
fn ByteWriter::finish(self : ByteWriter) -> Bytes {
  Bytes::from_array(self.bytes)
}

///|
priv struct ByteReader {
  data : Bytes
  mut position : Int
  limits : DecodeLimits
}

///|
fn ByteReader::new(data : Bytes, limits : DecodeLimits) -> ByteReader {
  { data, position: 0, limits }
}

///|
fn ByteReader::remaining(self : ByteReader) -> Int {
  self.data.length() - self.position
}

///|
fn ByteReader::read_u8(
  self : ByteReader,
  field : String,
) -> Int raise ArtifactDecodeError {
  if self.remaining() < 1 {
    raise Truncated(field~, offset=self.position, needed=1, remaining=0)
  }
  let value = self.data[self.position].to_int()
  self.position += 1
  value
}

///|
fn ByteReader::read_u32(
  self : ByteReader,
  field : String,
) -> Int raise ArtifactDecodeError {
  if self.remaining() < 4 {
    raise Truncated(
      field~,
      offset=self.position,
      needed=4,
      remaining=self.remaining(),
    )
  }
  let b0 = self.data[self.position].to_uint()
  let b1 = self.data[self.position + 1].to_uint()
  let b2 = self.data[self.position + 2].to_uint()
  let b3 = self.data[self.position + 3].to_uint()
  self.position += 4
  let value = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  if value > 0x7FFF_FFFFU {
    raise InvalidValue(
      field~,
      message="unsigned 32-bit value exceeds the host Int range",
    )
  }
  value.reinterpret_as_int()
}

///|
fn ByteReader::read_i64(
  self : ByteReader,
  field : String,
) -> Int64 raise ArtifactDecodeError {
  if self.remaining() < 8 {
    raise Truncated(
      field~,
      offset=self.position,
      needed=8,
      remaining=self.remaining(),
    )
  }
  let mut bits = 0UL
  for shift in 0..<8 {
    bits = bits |
      (self.data[self.position + shift].to_int().to_uint64() << (shift * 8))
  }
  self.position += 8
  bits.reinterpret_as_int64()
}

///|
fn ByteReader::read_bool(
  self : ByteReader,
  field : String,
) -> Bool raise ArtifactDecodeError {
  match self.read_u8(field) {
    0 => false
    1 => true
    tag => raise InvalidTag(field~, tag~)
  }
}

///|
fn ByteReader::read_raw(
  self : ByteReader,
  count : Int,
  field : String,
) -> Bytes raise ArtifactDecodeError {
  if count < 0 {
    raise InvalidValue(field~, message="negative byte count")
  }
  let remaining = self.remaining()
  if count > remaining {
    raise Truncated(field~, offset=self.position, needed=count, remaining~)
  }
  let result : Array[Byte] = []
  for i in 0..<count {
    result.push(self.data[self.position + i])
  }
  self.position += count
  Bytes::from_array(result)
}

///|
fn ByteReader::read_count(
  self : ByteReader,
  field : String,
  limit : Int,
) -> Int raise ArtifactDecodeError {
  let count = self.read_u32(field)
  if count > limit {
    raise LimitExceeded(field~, count~, limit~)
  }
  count
}

///|
fn ByteReader::read_string(
  self : ByteReader,
  field : String,
) -> String raise ArtifactDecodeError {
  let count = self.read_count(field + ".length", self.limits.max_string_bytes)
  let raw = self.read_raw(count, field)
  @utf8.decode(raw[:]) catch {
    _ => raise InvalidUtf8(field~)
  }
}

///|
fn bytes_to_array(bytes : Bytes) -> Array[Byte] {
  let result : Array[Byte] = []
  for byte in bytes {
    result.push(byte)
  }
  result
}

///|
fn write_architecture(
  writer : ByteWriter,
  value : @code_object.Architecture,
) -> Unit {
  writer.write_u8(
    match value {
      AArch64 => 0
      X64 => 1
    },
  )
}

///|
fn read_architecture(
  reader : ByteReader,
) -> @code_object.Architecture raise ArtifactDecodeError {
  match reader.read_u8("manifest.target.architecture") {
    0 => AArch64
    1 => X64
    tag => raise InvalidTag(field="manifest.target.architecture", tag~)
  }
}

///|
fn write_os_abi(writer : ByteWriter, value : OperatingSystemAbi) -> Unit {
  writer.write_u8(
    match value {
      MacOS => 0
      LinuxGnu => 1
      LinuxMusl => 2
      WindowsMsvc => 3
    },
  )
}

///|
fn read_os_abi(
  reader : ByteReader,
) -> OperatingSystemAbi raise ArtifactDecodeError {
  match reader.read_u8("manifest.target.operating_system_abi") {
    0 => MacOS
    1 => LinuxGnu
    2 => LinuxMusl
    3 => WindowsMsvc
    tag => raise InvalidTag(field="manifest.target.operating_system_abi", tag~)
  }
}

///|
fn write_endianness(writer : ByteWriter, value : @machv.Endianness) -> Unit {
  writer.write_u8(
    match value {
      Little => 0
      Big => 1
    },
  )
}

///|
fn read_endianness(
  reader : ByteReader,
) -> @machv.Endianness raise ArtifactDecodeError {
  match reader.read_u8("manifest.target.endianness") {
    0 => Little
    1 => Big
    tag => raise InvalidTag(field="manifest.target.endianness", tag~)
  }
}

///|
fn write_pointer_width(writer : ByteWriter, value : PointerWidth) -> Unit {
  match value {
    Bits64 => writer.write_u8(0)
  }
}

///|
fn read_pointer_width(
  reader : ByteReader,
) -> PointerWidth raise ArtifactDecodeError {
  match reader.read_u8("manifest.target.pointer_width") {
    0 => Bits64
    tag => raise InvalidTag(field="manifest.target.pointer_width", tag~)
  }
}

///|
fn write_optimization_level(
  writer : ByteWriter,
  value : OptimizationLevel,
) -> Unit {
  writer.write_u8(
    match value {
      O0 => 0
      O1 => 1
      O2 => 2
      O3 => 3
    },
  )
}

///|
fn read_optimization_level(
  reader : ByteReader,
) -> OptimizationLevel raise ArtifactDecodeError {
  match reader.read_u8("manifest.policy.optimization_level") {
    0 => O0
    1 => O1
    2 => O2
    3 => O3
    tag => raise InvalidTag(field="manifest.policy.optimization_level", tag~)
  }
}

///|
fn write_code_model(writer : ByteWriter, value : CodeModel) -> Unit {
  writer.write_u8(
    match value {
      Small => 0
      Large => 1
    },
  )
}

///|
fn read_code_model(reader : ByteReader) -> CodeModel raise ArtifactDecodeError {
  match reader.read_u8("manifest.policy.code_model") {
    0 => Small
    1 => Large
    tag => raise InvalidTag(field="manifest.policy.code_model", tag~)
  }
}

///|
fn write_call_binding(writer : ByteWriter, value : CallBinding) -> Unit {
  writer.write_u8(
    match value {
      StableEntry => 0
      DirectBody => 1
    },
  )
}

///|
fn read_call_binding(
  reader : ByteReader,
) -> CallBinding raise ArtifactDecodeError {
  match reader.read_u8("manifest.policy.call_binding") {
    0 => StableEntry
    1 => DirectBody
    tag => raise InvalidTag(field="manifest.policy.call_binding", tag~)
  }
}

///|
fn write_value_type(writer : ByteWriter, value : @machv.ValueType) -> Unit {
  writer.write_u8(
    match value {
      I32 => 0
      I64 => 1
      F32 => 2
      F64 => 3
      V128 => 4
      Ptr64 => 5
      GcRef64 => 6
    },
  )
}

///|
fn read_value_type(
  reader : ByteReader,
  field : String,
) -> @machv.ValueType raise ArtifactDecodeError {
  match reader.read_u8(field) {
    0 => I32
    1 => I64
    2 => F32
    3 => F64
    4 => V128
    5 => Ptr64
    6 => GcRef64
    tag => raise InvalidTag(field~, tag~)
  }
}

///|
fn write_signature(
  writer : ByteWriter,
  signature : @machv.Signature,
  field : String,
) -> Unit raise ArtifactEncodeError {
  writer.write_u32(signature.params.length(), field + ".params.length")
  for value in signature.params {
    write_value_type(writer, value)
  }
  writer.write_u32(signature.results.length(), field + ".results.length")
  for value in signature.results {
    write_value_type(writer, value)
  }
}

///|
fn read_signature(
  reader : ByteReader,
  field : String,
) -> @machv.Signature raise ArtifactDecodeError {
  let params_count = reader.read_count(
    field + ".params.length",
    reader.limits.max_signature_values,
  )
  let params : Array[@machv.ValueType] = []
  for _ in 0..<params_count {
    params.push(read_value_type(reader, field + ".params"))
  }
  let results_count = reader.read_count(
    field + ".results.length",
    reader.limits.max_signature_values,
  )
  let results : Array[@machv.ValueType] = []
  for _ in 0..<results_count {
    results.push(read_value_type(reader, field + ".results"))
  }
  @machv.Signature::new(params, results)
}

///|
fn write_source(
  writer : ByteWriter,
  source : @machv.SourceLocation,
  field : String,
) -> Unit raise ArtifactEncodeError {
  writer.write_string(source.file, field + ".file")
  writer.write_u32(source.line, field + ".line")
  writer.write_u32(source.column, field + ".column")
}

///|
fn read_source(
  reader : ByteReader,
  field : String,
) -> @machv.SourceLocation raise ArtifactDecodeError {
  @machv.SourceLocation::new(
    reader.read_string(field + ".file"),
    reader.read_u32(field + ".line"),
    reader.read_u32(field + ".column"),
  )
}

///|
fn write_optional_source(
  writer : ByteWriter,
  source : @machv.SourceLocation?,
  field : String,
) -> Unit raise ArtifactEncodeError {
  match source {
    None => writer.write_bool(false)
    Some(value) => {
      writer.write_bool(true)
      write_source(writer, value, field)
    }
  }
}

///|
fn read_optional_source(
  reader : ByteReader,
  field : String,
) -> @machv.SourceLocation? raise ArtifactDecodeError {
  if reader.read_bool(field + ".present") {
    Some(read_source(reader, field))
  } else {
    None
  }
}

///|
fn write_relocation_kind(
  writer : ByteWriter,
  kind : @code_object.RelocationKind,
) -> Unit {
  writer.write_u8(
    match kind {
      AArch64Call26 => 0
      AArch64Jump26 => 1
      AArch64Page21 => 2
      AArch64PageOffset12 => 3
      X64PcRelative32 => 4
      Absolute64 => 5
    },
  )
}

///|
fn read_relocation_kind(
  reader : ByteReader,
) -> @code_object.RelocationKind raise ArtifactDecodeError {
  match reader.read_u8("function.relocation.kind") {
    0 => AArch64Call26
    1 => AArch64Jump26
    2 => AArch64Page21
    3 => AArch64PageOffset12
    4 => X64PcRelative32
    5 => Absolute64
    tag => raise InvalidTag(field="function.relocation.kind", tag~)
  }
}

///|
fn write_relocation_target(
  writer : ByteWriter,
  target : @code_object.RelocationTarget,
) -> Unit raise ArtifactEncodeError {
  match target {
    Code(symbol) => {
      writer.write_u8(0)
      writer.write_string(symbol.name, "function.relocation.target.code")
    }
    External(symbol) => {
      writer.write_u8(1)
      writer.write_string(symbol.name, "function.relocation.target.external")
    }
    Data(symbol) => {
      writer.write_u8(2)
      writer.write_string(symbol.name, "function.relocation.target.data")
    }
  }
}

///|
fn read_relocation_target(
  reader : ByteReader,
) -> @code_object.RelocationTarget raise ArtifactDecodeError {
  match reader.read_u8("function.relocation.target") {
    0 =>
      Code(
        @machv.CodeSymbol::new(
          reader.read_string("function.relocation.target.code"),
        ),
      )
    1 =>
      External(
        @machv.ExternalSymbol::new(
          reader.read_string("function.relocation.target.external"),
        ),
      )
    2 =>
      Data(
        @machv.DataSymbol::new(
          reader.read_string("function.relocation.target.data"),
        ),
      )
    tag => raise InvalidTag(field="function.relocation.target", tag~)
  }
}

///|
fn write_trap_reason(writer : ByteWriter, reason : @machv.TrapReason) -> Unit {
  match reason {
    Unreachable => writer.write_u8(0)
    IntegerDivisionByZero => writer.write_u8(1)
    IntegerOverflow => writer.write_u8(2)
    InvalidConversionToInteger => writer.write_u8(3)
    MemoryOutOfBounds => writer.write_u8(4)
    TableOutOfBounds => writer.write_u8(5)
    IndirectCallTypeMismatch => writer.write_u8(6)
    NullReference => writer.write_u8(7)
    UnalignedAtomic => writer.write_u8(8)
    UnsupportedOperation => writer.write_u8(9)
    StackOverflow => writer.write_u8(10)
    User(value) => {
      writer.write_u8(11)
      writer.write_i64(value.to_int64())
    }
  }
}

///|
fn read_trap_reason(
  reader : ByteReader,
) -> @machv.TrapReason raise ArtifactDecodeError {
  match reader.read_u8("function.trap.reason") {
    0 => Unreachable
    1 => IntegerDivisionByZero
    2 => IntegerOverflow
    3 => InvalidConversionToInteger
    4 => MemoryOutOfBounds
    5 => TableOutOfBounds
    6 => IndirectCallTypeMismatch
    7 => NullReference
    8 => UnalignedAtomic
    9 => UnsupportedOperation
    10 => StackOverflow
    11 => User(reader.read_i64("function.trap.reason.user").to_int())
    tag => raise InvalidTag(field="function.trap.reason", tag~)
  }
}

///|
fn write_safepoint_kind(
  writer : ByteWriter,
  kind : @machv.SafepointKind,
) -> Unit {
  writer.write_u8(
    match kind {
      Gc => 0
      Cancellation => 1
      GcAndCancellation => 2
    },
  )
}

///|
fn read_safepoint_kind(
  reader : ByteReader,
) -> @machv.SafepointKind raise ArtifactDecodeError {
  match reader.read_u8("function.safepoint.kind") {
    0 => Gc
    1 => Cancellation
    2 => GcAndCancellation
    tag => raise InvalidTag(field="function.safepoint.kind", tag~)
  }
}

///|
fn write_register_bank(
  writer : ByteWriter,
  bank : @code_object.RegisterBank,
) -> Unit {
  writer.write_u8(
    match bank {
      Int => 0
      FpVector => 1
    },
  )
}

///|
fn read_register_bank(
  reader : ByteReader,
  field : String,
) -> @code_object.RegisterBank raise ArtifactDecodeError {
  match reader.read_u8(field) {
    0 => Int
    1 => FpVector
    tag => raise InvalidTag(field~, tag~)
  }
}

///|
fn write_root_location(
  writer : ByteWriter,
  root : @code_object.RootLocation,
) -> Unit raise ArtifactEncodeError {
  match root {
    Register(bank, index) => {
      writer.write_u8(0)
      write_register_bank(writer, bank)
      writer.write_u32(index, "function.safepoint.root.register")
    }
    Stack(offset~, ty~) => {
      writer.write_u8(1)
      writer.write_i64(offset.to_int64())
      write_value_type(writer, ty)
    }
  }
}

///|
fn read_root_location(
  reader : ByteReader,
) -> @code_object.RootLocation raise ArtifactDecodeError {
  match reader.read_u8("function.safepoint.root") {
    0 =>
      Register(
        read_register_bank(reader, "function.safepoint.root.register_bank"),
        reader.read_u32("function.safepoint.root.register"),
      )
    1 =>
      Stack(
        offset=reader.read_i64("function.safepoint.root.stack_offset").to_int(),
        ty=read_value_type(reader, "function.safepoint.root.stack_type"),
      )
    tag => raise InvalidTag(field="function.safepoint.root", tag~)
  }
}

///|
fn write_unwind_operation(
  writer : ByteWriter,
  operation : @code_object.UnwindOperation,
) -> Unit raise ArtifactEncodeError {
  match operation {
    StackAlloc(size~) => {
      writer.write_u8(0)
      writer.write_u32(size, "function.unwind.stack_size")
    }
    SetFramePointer(bank, index, cfa_offset~) => {
      writer.write_u8(1)
      write_register_bank(writer, bank)
      writer.write_u32(index, "function.unwind.register")
      writer.write_i64(cfa_offset.to_int64())
    }
    SaveRegister(bank, index, cfa_offset~) => {
      writer.write_u8(2)
      write_register_bank(writer, bank)
      writer.write_u32(index, "function.unwind.register")
      writer.write_i64(cfa_offset.to_int64())
    }
  }
}

///|
fn read_unwind_operation(
  reader : ByteReader,
) -> @code_object.UnwindOperation raise ArtifactDecodeError {
  match reader.read_u8("function.unwind.operation") {
    0 => StackAlloc(size=reader.read_u32("function.unwind.stack_size"))
    1 =>
      SetFramePointer(
        read_register_bank(reader, "function.unwind.register_bank"),
        reader.read_u32("function.unwind.register"),
        cfa_offset=reader.read_i64("function.unwind.cfa_offset").to_int(),
      )
    2 =>
      SaveRegister(
        read_register_bank(reader, "function.unwind.register_bank"),
        reader.read_u32("function.unwind.register"),
        cfa_offset=reader.read_i64("function.unwind.cfa_offset").to_int(),
      )
    tag => raise InvalidTag(field="function.unwind.operation", tag~)
  }
}

///|
fn write_digest(
  writer : ByteWriter,
  digest : Digest,
  field : String,
) -> Unit raise ArtifactEncodeError {
  if digest.bytes.length() != 32 {
    raise InvalidArtifactField(
      field~,
      message="expected exactly 32 SHA-256 bytes",
    )
  }
  writer.write_bytes(digest.bytes)
}

///|
fn read_digest(
  reader : ByteReader,
  field : String,
) -> Digest raise ArtifactDecodeError {
  { bytes: reader.read_raw(32, field) }
}

///|
fn write_manifest(
  writer : ByteWriter,
  manifest : CompatibilityManifest,
) -> Unit raise ArtifactEncodeError {
  if manifest.format_version != FORMAT_VERSION {
    raise InvalidArtifactField(
      field="manifest.format_version",
      message="expected version \{FORMAT_VERSION}",
    )
  }
  writer.write_u32(manifest.format_version, "manifest.format_version")
  write_architecture(writer, manifest.target.architecture)
  write_os_abi(writer, manifest.target.operating_system_abi)
  write_endianness(writer, manifest.target.endianness)
  write_pointer_width(writer, manifest.target.pointer_width)
  writer.write_u32(
    manifest.required_cpu_features.length(),
    "manifest.required_cpu_features.length",
  )
  for feature in manifest.required_cpu_features {
    writer.write_string(feature.name, "manifest.required_cpu_features.name")
  }
  writer.write_u32(manifest.jit_abi_version, "manifest.jit_abi_version")
  writer.write_string(manifest.codegen_revision, "manifest.codegen_revision")
  writer.write_string(
    manifest.module_identity.name,
    "manifest.module_identity.name",
  )
  write_digest(
    writer,
    manifest.module_identity.source_digest,
    "manifest.module_identity.source_digest",
  )
  write_digest(
    writer,
    manifest.module_identity.semantic_features_digest,
    "manifest.module_identity.semantic_features_digest",
  )
  write_optimization_level(writer, manifest.policy.optimization_level)
  write_code_model(writer, manifest.policy.code_model)
  write_call_binding(writer, manifest.policy.call_binding)
  writer.write_bool(manifest.policy.cancellation_safepoints)
  writer.write_bool(manifest.policy.debug_info)
}

///|
fn read_manifest(
  reader : ByteReader,
) -> CompatibilityManifest raise ArtifactDecodeError {
  let format_version = reader.read_u32("manifest.format_version")
  if format_version != FORMAT_VERSION {
    raise UnsupportedVersion(version=format_version)
  }
  let target : TargetSpec = {
    architecture: read_architecture(reader),
    operating_system_abi: read_os_abi(reader),
    endianness: read_endianness(reader),
    pointer_width: read_pointer_width(reader),
  }
  let feature_count = reader.read_count(
    "manifest.required_cpu_features.length",
    reader.limits.max_cpu_features,
  )
  let required_cpu_features : Array[CpuFeature] = []
  for _ in 0..<feature_count {
    required_cpu_features.push({
      name: reader.read_string("manifest.required_cpu_features.name"),
    })
  }
  let jit_abi_version = reader.read_u32("manifest.jit_abi_version")
  let codegen_revision = reader.read_string("manifest.codegen_revision")
  let module_identity : ModuleIdentity = {
    name: reader.read_string("manifest.module_identity.name"),
    source_digest: read_digest(reader, "manifest.module_identity.source_digest"),
    semantic_features_digest: read_digest(
      reader, "manifest.module_identity.semantic_features_digest",
    ),
  }
  let policy : CompilationPolicy = {
    optimization_level: read_optimization_level(reader),
    code_model: read_code_model(reader),
    call_binding: read_call_binding(reader),
    cancellation_safepoints: reader.read_bool(
      "manifest.policy.cancellation_safepoints",
    ),
    debug_info: reader.read_bool("manifest.policy.debug_info"),
  }
  {
    format_version,
    target,
    required_cpu_features,
    jit_abi_version,
    codegen_revision,
    module_identity,
    policy,
  }
}

///|
fn write_import(
  writer : ByteWriter,
  import_ : ImportIdentity,
) -> Unit raise ArtifactEncodeError {
  writer.write_u32(import_.function_index, "import.function_index")
  writer.write_string(import_.module_name, "import.module_name")
  writer.write_string(import_.function_name, "import.function_name")
  writer.write_string(import_.symbol.name, "import.symbol")
  write_signature(writer, import_.signature, "import.signature")
}

///|
fn read_import(reader : ByteReader) -> ImportIdentity raise ArtifactDecodeError {
  {
    function_index: reader.read_u32("import.function_index"),
    module_name: reader.read_string("import.module_name"),
    function_name: reader.read_string("import.function_name"),
    symbol: @machv.ExternalSymbol::new(reader.read_string("import.symbol")),
    signature: read_signature(reader, "import.signature"),
  }
}

///|
fn write_function(
  writer : ByteWriter,
  function : FunctionCode,
) -> Unit raise ArtifactEncodeError {
  writer.write_u32(
    function.identity.function_index,
    "function.identity.function_index",
  )
  writer.write_string(function.identity.symbol.name, "function.identity.symbol")
  write_signature(
    writer,
    function.identity.signature,
    "function.identity.signature",
  )
  writer.write_u32(function.entry_offset, "function.entry_offset")
  writer.write_u32(function.frame_size, "function.frame_size")
  writer.write_u32(function.code.length(), "function.code.length")
  writer.write_byte_array(function.code)
  writer.write_u32(function.relocations.length(), "function.relocations.length")
  for relocation in function.relocations {
    writer.write_u32(relocation.offset, "function.relocation.offset")
    write_relocation_kind(writer, relocation.kind)
    write_relocation_target(writer, relocation.target)
    writer.write_i64(relocation.addend)
  }
  writer.write_u32(function.sources.length(), "function.sources.length")
  for site in function.sources {
    writer.write_u32(site.offset, "function.source.offset")
    write_source(writer, site.source, "function.source")
  }
  writer.write_u32(function.traps.length(), "function.traps.length")
  for site in function.traps {
    writer.write_u32(site.offset, "function.trap.offset")
    write_trap_reason(writer, site.reason)
    write_optional_source(writer, site.source, "function.trap.source")
  }
  writer.write_u32(function.safepoints.length(), "function.safepoints.length")
  for site in function.safepoints {
    writer.write_u32(site.offset, "function.safepoint.offset")
    write_safepoint_kind(writer, site.kind)
    writer.write_u32(site.roots.length(), "function.safepoint.roots.length")
    for root in site.roots {
      write_root_location(writer, root)
    }
    write_optional_source(writer, site.source, "function.safepoint.source")
    match site.stack_map {
      None => writer.write_bool(false)
      Some(stack_map) => {
        writer.write_bool(true)
        writer.write_u32(stack_map.id, "function.safepoint.stack_map.id")
        writer.write_u32(
          stack_map.argument_root_count,
          "function.safepoint.stack_map.argument_root_count",
        )
      }
    }
  }
  writer.write_u32(function.unwind.length(), "function.unwind.length")
  for directive in function.unwind {
    writer.write_u32(directive.offset, "function.unwind.offset")
    write_unwind_operation(writer, directive.operation)
  }
}

///|
fn read_function(
  reader : ByteReader,
  architecture : @code_object.Architecture,
  total_code_bytes : Ref[Int],
) -> FunctionCode raise ArtifactDecodeError {
  let identity : FunctionIdentity = {
    function_index: reader.read_u32("function.identity.function_index"),
    symbol: @machv.CodeSymbol::new(
      reader.read_string("function.identity.symbol"),
    ),
    signature: read_signature(reader, "function.identity.signature"),
  }
  let entry_offset = reader.read_u32("function.entry_offset")
  let frame_size = reader.read_u32("function.frame_size")
  let code_count = reader.read_count(
    "function.code.length",
    reader.limits.max_code_bytes_per_function,
  )
  if code_count > reader.limits.max_total_code_bytes - total_code_bytes.val {
    raise LimitExceeded(
      field="artifact.total_code_bytes",
      count=total_code_bytes.val + code_count,
      limit=reader.limits.max_total_code_bytes,
    )
  }
  total_code_bytes.val += code_count
  let code = bytes_to_array(reader.read_raw(code_count, "function.code"))
  let entry_alignment = if architecture == AArch64 { 4 } else { 1 }
  if entry_offset >= code_count || entry_offset % entry_alignment != 0 {
    raise InvalidValue(
      field="function.entry_offset",
      message="offset is outside code or violates target instruction alignment",
    )
  }
  let relocation_count = reader.read_count(
    "function.relocations.length",
    reader.limits.max_relocations_per_function,
  )
  let relocations : Array[@code_object.Relocation] = []
  for _ in 0..<relocation_count {
    relocations.push(
      @code_object.Relocation::new(
        reader.read_u32("function.relocation.offset"),
        read_relocation_kind(reader),
        read_relocation_target(reader),
        addend=reader.read_i64("function.relocation.addend"),
      ),
    )
  }
  let source_count = reader.read_count(
    "function.sources.length",
    reader.limits.max_sources_per_function,
  )
  let sources : Array[@code_object.SourceSite] = []
  for _ in 0..<source_count {
    sources.push(
      @code_object.SourceSite::new(
        reader.read_u32("function.source.offset"),
        read_source(reader, "function.source"),
      ),
    )
  }
  let trap_count = reader.read_count(
    "function.traps.length",
    reader.limits.max_traps_per_function,
  )
  let traps : Array[@code_object.TrapSite] = []
  for _ in 0..<trap_count {
    traps.push(
      @code_object.TrapSite::new(
        reader.read_u32("function.trap.offset"),
        read_trap_reason(reader),
        source?=read_optional_source(reader, "function.trap.source"),
      ),
    )
  }
  let safepoint_count = reader.read_count(
    "function.safepoints.length",
    reader.limits.max_safepoints_per_function,
  )
  let safepoints : Array[@code_object.SafepointSite] = []
  for _ in 0..<safepoint_count {
    let offset = reader.read_u32("function.safepoint.offset")
    let kind = read_safepoint_kind(reader)
    let root_count = reader.read_count(
      "function.safepoint.roots.length",
      reader.limits.max_roots_per_safepoint,
    )
    let roots : Array[@code_object.RootLocation] = []
    for _ in 0..<root_count {
      roots.push(read_root_location(reader))
    }
    let source = read_optional_source(reader, "function.safepoint.source")
    let stack_map = if reader.read_bool("function.safepoint.stack_map.present") {
      Some(
        @machv.StackMapMetadata::new(
          reader.read_u32("function.safepoint.stack_map.id"),
          argument_root_count=reader.read_u32(
            "function.safepoint.stack_map.argument_root_count",
          ),
        ),
      )
    } else {
      None
    }
    safepoints.push(
      @code_object.SafepointSite::new(offset, kind, roots, source?, stack_map?),
    )
  }
  let unwind_count = reader.read_count(
    "function.unwind.length",
    reader.limits.max_unwind_directives_per_function,
  )
  let unwind : Array[@code_object.UnwindDirective] = []
  for _ in 0..<unwind_count {
    unwind.push(
      @code_object.UnwindDirective::new(
        reader.read_u32("function.unwind.offset"),
        read_unwind_operation(reader),
      ),
    )
  }
  {
    identity,
    entry_offset,
    frame_size,
    code,
    relocations,
    sources,
    traps,
    safepoints,
    unwind,
  }
}

///|
/// Encode one v9 Cwasm artifact without resolving symbolic relocations.
pub fn encode(artifact : Artifact) -> Bytes raise ArtifactEncodeError {
  let writer = ByteWriter::new()
  writer.write_byte_array([b'c', b'w', b'a', b's'])
  write_manifest(writer, artifact.manifest)
  writer.write_u32(artifact.imports.length(), "artifact.imports.length")
  for import_ in artifact.imports {
    write_import(writer, import_)
  }
  writer.write_u32(artifact.functions.length(), "artifact.functions.length")
  for function in artifact.functions {
    write_function(writer, function)
  }
  writer.finish()
}

///|
/// Decode untrusted v9 Cwasm bytes into ordinary artifact data.
///
/// This function performs bounded structural decoding only. The native
/// `wasmoon_jit` facade performs compatibility and code-object verification
/// before installation.
pub fn decode(
  data : Bytes,
  limits? : DecodeLimits = DecodeLimits::default(),
) -> Artifact raise ArtifactDecodeError {
  if data.length() > limits.max_artifact_bytes {
    raise ArtifactTooLarge(size=data.length(), limit=limits.max_artifact_bytes)
  }
  let reader = ByteReader::new(data, limits)
  let magic = reader.read_raw(4, "magic")
  if magic != Bytes::from_array([b'c', b'w', b'a', b's']) {
    raise BadMagic
  }
  let manifest = read_manifest(reader)
  let import_count = reader.read_count(
    "artifact.imports.length",
    limits.max_imports,
  )
  let imports : Array[ImportIdentity] = []
  for _ in 0..<import_count {
    imports.push(read_import(reader))
  }
  let function_count = reader.read_count(
    "artifact.functions.length",
    limits.max_functions,
  )
  let functions : Array[FunctionCode] = []
  let total_code_bytes = Ref(0)
  for _ in 0..<function_count {
    functions.push(
      read_function(reader, manifest.target.architecture, total_code_bytes),
    )
  }
  if reader.remaining() != 0 {
    raise TrailingBytes(count=reader.remaining())
  }
  { manifest, imports, functions }
}
