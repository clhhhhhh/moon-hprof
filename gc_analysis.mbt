///|
/// GC-root reachability and dominator analysis over recorded HPROF references.
/// Sizes are sums of HPROF payload bytes, not JVM shallow or retained heap.
pub struct GCAnalysis {
  reachable : Array[UInt64]
  unreachable_ids : Array[UInt64]
  roots : Array[UInt64]
  dominator : Map[UInt64, UInt64]
  retained_payload : Map[UInt64, Int64]
}

///|
fn intersect_ids(left : Array[UInt64], right : Array[UInt64]) -> Array[UInt64] {
  left.filter(id => right.contains(id))
}

///|
fn object_payload(heap : Summary, id : UInt64) -> Int64 {
  heap.object(id).map(obj => obj.payload_bytes.to_int64()).unwrap_or(0L)
}

///|
/// Compute the root-reachable object set and a conservative dominator tree.
/// The implementation intentionally uses bounded reference indexing so malformed
/// or unexpectedly large dumps fail rather than silently producing partial data.
pub fn Summary::gc_analysis(
  self : Summary,
  max_edges? : Int = 1_000_000,
  max_slots? : Int = 10_000_000,
) -> GCAnalysis raise ParseError {
  let index = ReferenceIndex::build(self, max_edges~, max_slots~)
  let roots = []
  for root in self.roots_data {
    if index.known_nodes.contains(root.object_id) &&
      !roots.contains(root.object_id) {
      roots.push(root.object_id)
    }
  }
  let reachable = []
  let queue = roots.copy()
  let mut cursor = 0
  while cursor < queue.length() {
    let id = queue[cursor]
    cursor += 1
    if reachable.contains(id) {
      continue
    }
    reachable.push(id)
    let outgoing = index.outbound.get(id).unwrap_or([])
    for edge in outgoing {
      if index.known_nodes.contains(edge.target_id) &&
        !reachable.contains(edge.target_id) {
        queue.push(edge.target_id)
      }
    }
  }
  reachable.sort()
  let all = index.known_nodes.keys().to_array()
  all.sort()
  let unreachable_ids = all.filter(id => !reachable.contains(id))
  let dominators : Map[UInt64, Array[UInt64]] = Map([])
  for id in reachable {
    dominators[id] = if roots.contains(id) { [id] } else { reachable.copy() }
  }
  let mut changed = true
  let mut rounds = 0
  while changed && rounds < reachable.length() + 1 {
    changed = false
    rounds += 1
    for id in reachable {
      if roots.contains(id) {
        continue
      }
      let predecessors = index.inbound
        .get(id)
        .unwrap_or([])
        .filter(edge => reachable.contains(edge.source_id))
        .map(edge => dominators.get(edge.source_id).unwrap_or([]))
      let next = if predecessors.is_empty() {
        [id]
      } else {
        let mut candidate = predecessors[0].copy()
        for set in predecessors[1:] {
          candidate = intersect_ids(candidate, set)
        }
        if !candidate.contains(id) {
          candidate.push(id)
        }
        candidate.sort()
        candidate
      }
      if dominators[id] != next {
        dominators[id] = next
        changed = true
      }
    }
  }
  let dominator = Map([])
  for id in reachable {
    let candidates = dominators[id].filter(candidate => candidate != id)
    if candidates.length() > 0 {
      let mut best = candidates[0]
      for candidate in candidates[1:] {
        if dominators[candidate].length() > dominators[best].length() {
          best = candidate
        }
      }
      dominator[id] = best
    }
  }
  let retained_payload : Map[UInt64, Int64] = Map([])
  for id in reachable {
    let mut total = 0L
    for candidate in reachable {
      if dominators[candidate].contains(id) {
        total += object_payload(self, candidate)
      }
    }
    retained_payload[id] = total
  }
  { reachable, unreachable_ids, roots, dominator, retained_payload, }
}

///|
pub fn GCAnalysis::is_reachable(self : GCAnalysis, id : UInt64) -> Bool {
  self.reachable.contains(id)
}

///|
pub fn GCAnalysis::dominator_of(self : GCAnalysis, id : UInt64) -> UInt64? {
  self.dominator.get(id)
}

///|
pub fn GCAnalysis::retained_payload(self : GCAnalysis, id : UInt64) -> Int64 {
  self.retained_payload.get(id).unwrap_or(0L)
}

///|
/// JSON report with root/reachability counts and the highest retained payloads.
pub fn GCAnalysis::to_json(
  self : GCAnalysis,
  limit? : Int = 100,
) -> Json raise ParseError {
  if limit < 0 || limit > 100_000 {
    raise Invalid(0, "GC report limit must be between 0 and 100000")
  }
  let ids = self.reachable.copy()
  ids.sort_by((left, right) => {
    let left_size = self.retained_payload(left)
    let right_size = self.retained_payload(right)
    if left_size != right_size {
      right_size.compare(left_size)
    } else {
      left.compare(right)
    }
  })
  let count = if limit < ids.length() { limit } else { ids.length() }
  Json::object({
    "root_count": json_int(self.roots.length()),
    "reachable_count": json_int(self.reachable.length()),
    "unreachable_count": json_int(self.unreachable_ids.length()),
    "objects": Json::array(
      ids[:count].map(id => {
        Json::object({
          "object_id": json_id(id),
          "immediate_dominator": self
          .dominator_of(id)
          .map(json_id)
          .unwrap_or(Json::null()),
          "retained_payload_bytes": Json::string(
            self.retained_payload(id).to_string(),
          ),
        })
      }),
    ),
  })
}
