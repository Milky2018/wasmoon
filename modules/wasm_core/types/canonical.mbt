// Group fingerprints for isorecursive type hash-consing.
//
// A fingerprint is a necessary condition for structural equivalence of two
// rec groups: members are hashed in group order, references inside the group
// are encoded by position, and references to other types are encoded by an
// identity the caller supplies (a canonical index or a store-wide identity).
// Rec groups only reference earlier groups or their own members, so callers
// can supply identities lazily while visiting groups in definition order.
// Hash collisions are allowed; exact equivalence is decided by
// TypeEquivalenceContext after the fingerprint narrows the candidates.

///|
/// Rotate a 64-bit value left; shift counts stay below 64 so shifts are
/// always defined. The whole fingerprint pipeline runs in UInt64: the C
/// backend lowers signed shifts of negative values to undefined behavior,
/// which UBSan rejects, while unsigned shifts are always defined.
fn rotl64(x : UInt64, n : Int) -> UInt64 {
  (x << n) | (x >> (64 - n))
}

///|
/// Mix one token into the accumulator. Uses rotations and xor only:
/// native debug builds trap on signed integer overflow, so fingerprint
/// hashing must not rely on wrapping multiplication.
fn mix_token(acc : UInt64, token : UInt64) -> UInt64 {
  let mixed = rotl64(acc, 11) ^ token
  mixed ^ (mixed >> 13)
}

///|
/// Final avalanche over a whole group fingerprint.
fn avalanche64(x : UInt64) -> UInt64 {
  let x = x ^ (x >> 12)
  let x = x ^ (x << 25)
  x ^ (x >> 27)
}

///|
/// Encoded references may be negative (group positions, offset abstract
/// heap types); mixing keeps their bit patterns.
fn mix_ref(acc : UInt64, ref_ : Int32) -> UInt64 {
  mix_token(acc, ref_.to_int64().reinterpret_as_uint64())
}

///|
/// Hash one value type. Type references are resolved through `encode_ref`,
/// which must already distinguish group-internal positions from external
/// identities.
fn hash_value_type(
  acc : UInt64,
  value_type : ValueType,
  encode_ref : (Int32) -> Int32,
) -> UInt64 {
  match value_type {
    I32 => mix_token(acc, 101UL)
    I64 => mix_token(acc, 103UL)
    F32 => mix_token(acc, 105UL)
    F64 => mix_token(acc, 107UL)
    V128 => mix_token(acc, 109UL)
    FuncRef => mix_token(acc, 111UL)
    ExternRef => mix_token(acc, 113UL)
    RefFunc => mix_token(acc, 115UL)
    RefExtern => mix_token(acc, 117UL)
    RefFuncTyped(ref_) => mix_ref(mix_token(acc, 119UL), encode_ref(ref_))
    RefNullFuncTyped(ref_) => mix_ref(mix_token(acc, 121UL), encode_ref(ref_))
    ContRef => mix_token(acc, 123UL)
    RefCont => mix_token(acc, 125UL)
    RefContTyped(ref_) => mix_ref(mix_token(acc, 127UL), encode_ref(ref_))
    RefNullContTyped(ref_) => mix_ref(mix_token(acc, 129UL), encode_ref(ref_))
    NullContRef => mix_token(acc, 131UL)
    RefNoCont => mix_token(acc, 133UL)
    AnyRef => mix_token(acc, 135UL)
    ExnRef => mix_token(acc, 137UL)
    StructRef => mix_token(acc, 139UL)
    ArrayRef => mix_token(acc, 141UL)
    RefStruct(ref_) => mix_ref(mix_token(acc, 143UL), encode_ref(ref_))
    RefNullStruct(ref_) => mix_ref(mix_token(acc, 145UL), encode_ref(ref_))
    RefArray(ref_) => mix_ref(mix_token(acc, 147UL), encode_ref(ref_))
    RefNullArray(ref_) => mix_ref(mix_token(acc, 149UL), encode_ref(ref_))
    RefAny => mix_token(acc, 151UL)
    RefEq => mix_token(acc, 153UL)
    RefNullEq => mix_token(acc, 155UL)
    RefI31 => mix_token(acc, 157UL)
    RefNullI31 => mix_token(acc, 159UL)
    RefStructAbs => mix_token(acc, 161UL)
    RefArrayAbs => mix_token(acc, 163UL)
    RefNone => mix_token(acc, 165UL)
    NullRef => mix_token(acc, 167UL)
    NullFuncRef => mix_token(acc, 169UL)
    NullExnRef => mix_token(acc, 171UL)
    NullExternRef => mix_token(acc, 173UL)
  }
}

///|
fn hash_field_type(
  acc : UInt64,
  field : FieldType,
  encode_ref : (Int32) -> Int32,
) -> UInt64 {
  let acc = mix_token(acc, if field.mutable { 211UL } else { 213UL })
  match field.storage_type {
    Val(value_type) => hash_value_type(acc, value_type, encode_ref)
    Packed(I8) => mix_token(acc, 221UL)
    Packed(I16) => mix_token(acc, 223UL)
  }
}

///|
fn hash_composite_type(
  acc : UInt64,
  composite : CompositeType,
  encode_ref : (Int32) -> Int32,
) -> UInt64 {
  match composite {
    Func(func_type) => {
      let mut acc = mix_token(acc, 301UL)
      acc = mix_token(acc, func_type.params.length().to_uint64())
      for param in func_type.params {
        acc = hash_value_type(acc, param, encode_ref)
      }
      acc = mix_token(acc, func_type.results.length().to_uint64())
      for result in func_type.results {
        acc = hash_value_type(acc, result, encode_ref)
      }
      acc
    }
    Struct(struct_type) => {
      let mut acc = mix_token(acc, 303UL)
      acc = mix_token(acc, struct_type.fields.length().to_uint64())
      for field in struct_type.fields {
        acc = hash_field_type(acc, field, encode_ref)
      }
      acc
    }
    Array(array_type) =>
      hash_field_type(mix_token(acc, 305UL), array_type.element, encode_ref)
    Cont(ref_) => mix_ref(mix_token(acc, 307UL), encode_ref(ref_))
  }
}

///|
fn hash_sub_type(
  acc : UInt64,
  subtype : SubType,
  encode_ref : (Int32) -> Int32,
) -> UInt64 {
  let mut acc = mix_token(acc, if subtype.final_ { 401UL } else { 403UL })
  acc = mix_token(acc, subtype.supertypes.length().to_uint64())
  for supertype in subtype.supertypes {
    acc = mix_ref(acc, encode_ref(supertype))
  }
  hash_composite_type(acc, subtype.composite, encode_ref)
}

///|
/// Visit every rec group of a type section in definition order, together with
/// a structural fingerprint of the whole group. `external_identity` resolves a
/// reference to a type outside the group being visited; it is only asked
/// about types in groups visited earlier, which is where the binary format
/// allows such references to point.
pub fn fold_type_groups(
  types : ArrayView[SubType],
  type_rec_groups~ : ArrayView[Int32] = [],
  external_identity~ : (Int32) -> Int32,
  visit~ : (ArrayView[Int32], Int64) -> Unit,
) -> Unit {
  let index = RecGroupIndex::new(types.length(), type_rec_groups)
  for group_id in 0..<index.groups.length() {
    let members = index.groups[group_id]
    let mut acc : UInt64 = 2685821657746797981UL
    acc = mix_token(acc, members.length().to_uint64())
    for type_index in members {
      let current_group = group_id
      let encode_ref = fn(ref_ : Int32) -> Int32 {
        // Group-internal references compare by position; references to
        // concrete types in other groups are resolved through the caller's
        // identity map. Fingerprints are necessary-condition keys, not
        // injections: encodings only need to distinguish reference classes,
        // and exact equivalence is re-verified structurally per bucket.
        // Negative indices name abstract heap types (for example the WAT
        // `arrayref` shorthand); they are offset away from the group-position
        // range so the two classes never share a token.
        if ref_ < 0 {
          ref_ - 0x4000_0000
        } else if index.group_at(ref_) == current_group {
          -(index.position_by_type[ref_] + 1)
        } else {
          external_identity(ref_)
        }
      }
      acc = hash_sub_type(acc, types[type_index], encode_ref)
    }
    visit(members, avalanche64(acc).reinterpret_as_int64())
  }
}
