///|
priv suberror CanonicalLayoutError {
  CanonicalLayoutError
}

///|
pub fn canonical_discriminant_layout(case_count : Int) -> (Int, Int) {
  if case_count <= 0x100 {
    (1, 1)
  } else if case_count <= 0x10000 {
    (2, 2)
  } else {
    (4, 4)
  }
}

///|
pub fn canonical_memory_layout(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> (Int, Int)? {
  let visiting : Map[Int, Unit] = Map([])
  fn align_to(size : Int, alignment : Int) -> Int raise CanonicalLayoutError {
    let result = (size.to_int64() + alignment.to_int64() - 1L) /
      alignment.to_int64() *
      alignment.to_int64()
    if result > 2147483647L {
      raise CanonicalLayoutError
    }
    result.to_int()
  }
  fn add(a : Int, b : Int) -> Int raise CanonicalLayoutError {
    if a > 2147483647 - b {
      raise CanonicalLayoutError
    }
    a + b
  }
  fn layout(ty : ValType) -> (Int, Int) raise CanonicalLayoutError {
    match ty {
      Prim(p) =>
        match p {
          Bool | S8 | U8 => (1, 1)
          S16 | U16 => (2, 2)
          S32 | U32 | Char | F32 | ErrorContext => (4, 4)
          S64 | U64 | F64 => (8, 8)
          String => if mem_is_64 { (16, 8) } else { (8, 4) }
        }
      TypeIdx(idx) => {
        if visiting.get(idx) is Some(_) {
          raise CanonicalLayoutError
        }
        visiting.set(idx, ())
        defer visiting.remove(idx)
        match types.get(idx) {
          Some(Some(DefValType(p))) => layout(Prim(p))
          Some(Some(FixedList(element, length))) => {
            let (size, alignment) = layout(element)
            let stride = align_to(size, alignment)
            if length < 0 || (stride != 0 && length > 2147483647 / stride) {
              raise CanonicalLayoutError
            }
            (stride * length, alignment)
          }
          Some(Some(Tuple(items))) => {
            let mut size = 0
            let mut alignment = 1
            for item in items {
              let (item_size, item_alignment) = layout(item)
              size = add(align_to(size, item_alignment), item_size)
              if item_alignment > alignment {
                alignment = item_alignment
              }
            }
            (align_to(size, alignment), alignment)
          }
          Some(Some(Record(fields))) => {
            let mut size = 0
            let mut alignment = 1
            for field in fields {
              let (field_size, field_alignment) = layout(field.ty)
              size = add(align_to(size, field_alignment), field_size)
              if field_alignment > alignment {
                alignment = field_alignment
              }
            }
            (align_to(size, alignment), alignment)
          }
          Some(Some(List(_))) => if mem_is_64 { (16, 8) } else { (8, 4) }
          Some(Some(Enum(labels))) =>
            canonical_discriminant_layout(labels.length())
          Some(Some(Flags(labels))) => {
            let words = (labels.length() + 31) / 32
            if words == 0 {
              (0, 1)
            } else if labels.length() <= 8 {
              (1, 1)
            } else if labels.length() <= 16 {
              (2, 2)
            } else {
              (words * 4, 4)
            }
          }
          Some(Some(Variant(cases))) => {
            let (tag_size, tag_alignment) = canonical_discriminant_layout(
              cases.length(),
            )
            let mut payload_size = 0
            let mut payload_alignment = 1
            for case in cases {
              match case.ty {
                Some(payload) => {
                  let (size, alignment) = layout(payload)
                  if size > payload_size {
                    payload_size = size
                  }
                  if alignment > payload_alignment {
                    payload_alignment = alignment
                  }
                }
                None => ()
              }
            }
            let alignment = if tag_alignment > payload_alignment {
              tag_alignment
            } else {
              payload_alignment
            }
            let payload_offset = align_to(tag_size, payload_alignment)
            (align_to(add(payload_offset, payload_size), alignment), alignment)
          }
          Some(Some(Option(payload))) => {
            let (payload_size, payload_alignment) = layout(payload)
            let payload_offset = align_to(1, payload_alignment)
            (
              align_to(add(payload_offset, payload_size), payload_alignment),
              payload_alignment,
            )
          }
          Some(Some(Result(ok, err))) => {
            let mut payload_size = 0
            let mut payload_alignment = 1
            for payload in [ok, err] {
              match payload {
                Some(value) => {
                  let (size, alignment) = layout(value)
                  if size > payload_size {
                    payload_size = size
                  }
                  if alignment > payload_alignment {
                    payload_alignment = alignment
                  }
                }
                None => ()
              }
            }
            let payload_offset = align_to(1, payload_alignment)
            (
              align_to(add(payload_offset, payload_size), payload_alignment),
              payload_alignment,
            )
          }
          Some(Some(Own(_)))
          | Some(Some(Borrow(_)))
          | Some(Some(ResourceType(_, _, _, _)))
          | Some(Some(Stream(_)))
          | Some(Some(Future(_))) => (4, 4)
          _ => raise CanonicalLayoutError
        }
      }
    }
  }
  try layout(ty) catch {
    CanonicalLayoutError => None
  } noraise {
    result => Some(result)
  }
}
