///|
pub(all) struct ActiveReloadCache {
  epoch : Array[Int]
  preg_ids : Array[Int]
} derive(Debug)

///|
pub fn ActiveReloadCache::ActiveReloadCache(
  slot_count : Int,
) -> ActiveReloadCache {
  { epoch: Array::make(slot_count, 0), preg_ids: Array::make(slot_count, -1) }
}

///|
pub fn ActiveReloadCache::get(
  self : ActiveReloadCache,
  slot : Int,
  epoch : Int,
) -> Int? {
  if slot < 0 || slot >= self.epoch.length() {
    return None
  }
  if self.epoch[slot] == epoch {
    Some(self.preg_ids[slot])
  } else {
    None
  }
}

///|
pub fn ActiveReloadCache::set(
  self : ActiveReloadCache,
  slot : Int,
  preg_id : Int,
  epoch : Int,
) -> Unit {
  if slot < 0 || slot >= self.epoch.length() {
    return
  }
  self.epoch[slot] = epoch
  self.preg_ids[slot] = preg_id
}

///|
pub fn ActiveReloadCache::clear(self : ActiveReloadCache, slot : Int) -> Unit {
  if slot < 0 || slot >= self.epoch.length() {
    return
  }
  self.epoch[slot] = 0
}
