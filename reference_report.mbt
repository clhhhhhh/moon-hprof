///|
/// Direct reference counts only; source_count does not measure retained size.
pub struct ReferencedObject {
  object_id : UInt64
  reference_count : Int
  source_count : Int
  present_in_heap : Bool
}

///|
/// Distinct source objects, unlike incoming(), which preserves every edge.
pub fn ReferenceIndex::referrer_ids(
  self : ReferenceIndex,
  id : UInt64,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Array[UInt64] raise ParseError {
  let unique : Map[UInt64, Bool] = Map([])
  for edge in self.inbound.get(id).unwrap_or([]) {
    unique[edge.source_id] = true
  }
  let ids = unique.keys().to_array()
  ids.sort()
  let end = page_end(offset, limit, ids.length())
  ids[offset:end].to_owned()
}

///|
/// Ranks targets by distinct referring objects, then edge count, then ID.
/// Multiple array slots or fields in one source are not multiple sources.
pub fn ReferenceIndex::most_referenced(
  self : ReferenceIndex,
  limit? : Int = 20,
) -> Array[ReferencedObject] raise ParseError {
  let end = page_end(0, limit, self.inbound.length())
  if end == 0 {
    return []
  }
  let result = []
  for id, edges in self.inbound {
    let sources : Map[UInt64, Bool] = Map([])
    for edge in edges {
      sources[edge.source_id] = true
    }
    result.push({
      object_id: id,
      reference_count: edges.length(),
      source_count: sources.length(),
      present_in_heap: self.known_nodes.contains(id),
    })
  }
  result.sort_by((a, b) => {
    let sources = b.source_count.compare(a.source_count)
    if sources != 0 {
      sources
    } else {
      let edges = b.reference_count.compare(a.reference_count)
      if edges != 0 {
        edges
      } else {
        a.object_id.compare(b.object_id)
      }
    }
  })
  result[0:end].to_owned()
}

///|
pub fn ReferencedObject::to_json(self : ReferencedObject) -> Json {
  Json::object({
    "object_id": json_id(self.object_id),
    "reference_count": json_int(self.reference_count),
    "source_count": json_int(self.source_count),
    "present_in_heap": Json::boolean(self.present_in_heap),
  })
}
