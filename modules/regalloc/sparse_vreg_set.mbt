///|
priv enum SparseVRegWords {
  Small(Array[(Int, UInt64)])
  Large(Map[Int, UInt64])
  Dense(Array[UInt64])
}

///|
priv struct SparseVRegSet {
  mut words : SparseVRegWords
}

///|
fn SparseVRegSet::new() -> SparseVRegSet {
  { words: Small([]), }
}

///|
fn SparseVRegSet::dense(value_count : Int) -> SparseVRegSet {
  { words: Dense(Array::make((value_count + 63) / 64, 0UL)), }
}

///|
fn SparseVRegSet::word(self : SparseVRegSet, word_id : Int) -> UInt64 {
  match self.words {
    Small(entries) => {
      for entry in entries {
        if entry.0 == word_id {
          return entry.1
        }
      }
      0UL
    }
    Large(words) => words.get(word_id).unwrap_or(0UL)
    Dense(words) => words.get(word_id).unwrap_or(0UL)
  }
}

///|
fn SparseVRegSet::set_word(
  self : SparseVRegSet,
  word_id : Int,
  bits : UInt64,
) -> Unit {
  match self.words {
    Small(entries) => {
      for index, entry in entries {
        if entry.0 == word_id {
          if bits == 0UL {
            entries.remove(index) |> ignore
          } else {
            entries[index] = (word_id, bits)
          }
          return
        }
      }
      if bits == 0UL {
        return
      }
      if entries.length() < 8 {
        entries.push((word_id, bits))
      } else {
        let words : Map[Int, UInt64] = Map([])
        for entry in entries {
          words[entry.0] = entry.1
        }
        words[word_id] = bits
        self.words = Large(words)
      }
    }
    Large(words) =>
      if bits == 0UL {
        words.remove(word_id)
      } else {
        words[word_id] = bits
      }
    Dense(words) =>
      if word_id >= 0 && word_id < words.length() {
        words[word_id] = bits
      }
  }
}

///|
fn SparseVRegSet::set(self : SparseVRegSet, id : Int, present : Bool) -> Unit {
  if id < 0 {
    return
  }
  let word_id = id / 64
  let bit = id % 64
  let mask = 1UL << bit
  let old = self.word(word_id)
  self.set_word(word_id, if present { old | mask } else { old & mask.lnot() })
}

///|
fn SparseVRegSet::contains(self : SparseVRegSet, id : Int) -> Bool {
  if id < 0 {
    return false
  }
  let word_id = id / 64
  let bit = id % 64
  (self.word(word_id) & (1UL << bit)) != 0UL
}

///|
fn SparseVRegSet::merge_word(
  self : SparseVRegSet,
  word_id : Int,
  bits : UInt64,
) -> Bool {
  if bits == 0UL {
    return false
  }
  let old = self.word(word_id)
  let combined = old | bits
  if combined == old {
    false
  } else {
    self.set_word(word_id, combined)
    true
  }
}

///|
fn SparseVRegSet::union_with(
  self : SparseVRegSet,
  other : SparseVRegSet,
) -> Bool {
  let mut changed = false
  match (self.words, other.words) {
    (Dense(destination), Dense(source)) => {
      for word_id, bits in source {
        let combined = destination[word_id] | bits
        if combined != destination[word_id] {
          destination[word_id] = combined
          changed = true
        }
      }
      return changed
    }
    _ => ()
  }
  match other.words {
    Small(entries) =>
      for entry in entries {
        if self.merge_word(entry.0, entry.1) {
          changed = true
        }
      }
    Large(words) =>
      for word_id, bits in words {
        if self.merge_word(word_id, bits) {
          changed = true
        }
      }
    Dense(words) =>
      for word_id, bits in words {
        if self.merge_word(word_id, bits) {
          changed = true
        }
      }
  }
  changed
}

///|
fn SparseVRegSet::union_without(
  self : SparseVRegSet,
  other : SparseVRegSet,
  excluded : SparseVRegSet,
) -> Bool {
  let mut changed = false
  match (self.words, other.words, excluded.words) {
    (Dense(destination), Dense(source), Dense(mask)) => {
      for word_id, bits in source {
        let combined = destination[word_id] | (bits & mask[word_id].lnot())
        if combined != destination[word_id] {
          destination[word_id] = combined
          changed = true
        }
      }
      return changed
    }
    _ => ()
  }
  match other.words {
    Small(entries) =>
      for entry in entries {
        if self.merge_word(entry.0, entry.1 & excluded.word(entry.0).lnot()) {
          changed = true
        }
      }
    Large(words) =>
      for word_id, bits in words {
        if self.merge_word(word_id, bits & excluded.word(word_id).lnot()) {
          changed = true
        }
      }
    Dense(words) =>
      for word_id, bits in words {
        if self.merge_word(word_id, bits & excluded.word(word_id).lnot()) {
          changed = true
        }
      }
  }
  changed
}

///|
fn SparseVRegSet::to_sorted_array(self : SparseVRegSet) -> Array[Int] {
  let values : Array[Int] = []
  fn append_word(values : Array[Int], word_id : Int, bits : UInt64) -> Unit {
    let mut remaining = bits
    while remaining != 0UL {
      let bit = remaining.ctz()
      values.push(word_id * 64 + bit)
      remaining = remaining & (remaining - 1UL)
    }
  }
  match self.words {
    Small(entries) =>
      for entry in entries {
        append_word(values, entry.0, entry.1)
      }
    Large(words) =>
      for word_id, bits in words {
        append_word(values, word_id, bits)
      }
    Dense(words) =>
      for word_id, bits in words {
        append_word(values, word_id, bits)
      }
  }
  values.sort_by((a, b) => a - b)
  values
}
