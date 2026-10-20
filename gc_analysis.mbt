///|
/// GC-root reachability and dominator analysis over HPROF reference metadata.
/// Sizes are sums of HPROF payload bytes, not JVM shallow or retained heap.
pub struct GCAnalysis {
  reachable : Array[UInt64]
  unreachable_ids : Array[UInt64]
  roots : Array[UInt64]
  dominator : Map[UInt64, UInt64]
  retained_payload : Map[UInt64, Int64]
  priv index : ReferenceIndex
  priv weak_reference_labels : Map[String, Bool]
}

///|
pub struct GCRootPath {
  root_id : UInt64
  edges : Array[ReferenceEdge]
}

///|
fn object_payload(heap : Summary, id : UInt64) -> Int64 {
  heap.object(id).map(obj => obj.payload_bytes.to_int64()).unwrap_or(0L)
}

///|
/// Virtual node zero represents the common parent of all roots.
fn intersect_dominator(
  left : UInt64,
  right : UInt64,
  dominator : Map[UInt64, UInt64],
  order : Map[UInt64, Int],
) -> UInt64 {
  let mut a = left
  let mut b = right
  while a != b {
    let rank_a = if a == 0UL { -1 } else { order.get(a).unwrap_or(-1) }
    let rank_b = if b == 0UL { -1 } else { order.get(b).unwrap_or(-1) }
    if rank_a > rank_b {
      a = dominator.get(a).unwrap_or(0UL)
    } else {
      b = dominator.get(b).unwrap_or(0UL)
    }
  }
  a
}

///|
/// Compute root reachability and immediate dominators using iterative dataflow.
/// The implementation intentionally uses bounded reference indexing so malformed
/// or unexpectedly large dumps fail rather than silently producing partial data.
pub fn Summary::gc_analysis(
  self : Summary,
  max_edges? : Int = 1_000_000,
  max_slots? : Int = 10_000_000,
) -> GCAnalysis raise ParseError {
  let index = ReferenceIndex::build(self, max_edges~, max_slots~)
  let weak_reference_labels : Map[String, Bool] = Map([])
  for class_id in self.class_ids() {
    if self.class_name(class_id) == Some("java/lang/ref/Reference") {
      for field in self.definitions[class_id].fields {
        if self.string(field.name_id) == Some("referent") {
          weak_reference_labels["\{class_id}:referent"] = true
        }
      }
    }
  }
  let roots = []
  for root in self.roots_data {
    if index.known_nodes.contains(root.object_id) &&
      !roots.contains(root.object_id) {
      roots.push(root.object_id)
    }
  }
  let reachable = []
  let discovered : Map[UInt64, Bool] = Map([])
  let queue = roots.copy()
  for id in roots {
    discovered[id] = true
  }
  let mut cursor = 0
  while cursor < queue.length() {
    let id = queue[cursor]
    cursor += 1
    reachable.push(id)
    let outgoing = index.outbound.get(id).unwrap_or([])
    for edge in outgoing {
      if !weak_reference_labels.contains(edge.label) &&
        index.known_nodes.contains(edge.target_id) &&
        !discovered.contains(edge.target_id) {
        discovered[edge.target_id] = true
        queue.push(edge.target_id)
      }
    }
  }
  let order : Map[UInt64, Int] = Map([])
  for i in 0..<reachable.length() {
    order[reachable[i]] = i
  }
  let all = index.known_nodes.keys().to_array()
  all.sort()
  let unreachable_ids = all.filter(id => !discovered.contains(id))
  // A zero parent denotes the synthetic root shared by all HPROF roots.
  let dominator : Map[UInt64, UInt64] = Map([])
  for id in roots {
    dominator[id] = 0UL
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
        .filter(edge => {
          discovered.contains(edge.source_id) &&
          !weak_reference_labels.contains(edge.label) &&
          dominator.contains(edge.source_id)
        })
      if predecessors.length() > 0 {
        let mut next = predecessors[0].source_id
        for edge in predecessors[1:] {
          next = intersect_dominator(next, edge.source_id, dominator, order)
        }
        if dominator.get(id) != Some(next) {
          dominator[id] = next
          changed = true
        }
      }
    }
  }
  if changed {
    raise Invalid(0, "immediate-dominator analysis did not converge")
  }
  let retained_payload : Map[UInt64, Int64] = Map([])
  for id in reachable {
    retained_payload[id] = object_payload(self, id)
  }
  // BFS discovers every dominator before its descendants, so reverse order is
  // a dominator-tree postorder even when object IDs have unrelated ordering.
  for id in reachable.rev() {
    let parent = dominator.get(id).unwrap_or(0UL)
    if parent != 0UL {
      retained_payload[parent] = retained_payload[parent] + retained_payload[id]
    }
  }
  reachable.sort()
  {
    reachable,
    unreachable_ids,
    roots,
    dominator,
    retained_payload,
    index,
    weak_reference_labels,
  }
}

///|
pub fn GCAnalysis::is_reachable(self : GCAnalysis, id : UInt64) -> Bool {
  self.reachable.contains(id)
}

///|
pub fn GCAnalysis::dominator_of(self : GCAnalysis, id : UInt64) -> UInt64? {
  match self.dominator.get(id) {
    Some(0UL) | None => None
    Some(parent) => Some(parent)
  }
}

///|
pub fn GCAnalysis::retained_payload(self : GCAnalysis, id : UInt64) -> Int64 {
  self.retained_payload.get(id).unwrap_or(0L)
}

///|
/// Return the shortest strong-reference path from any recorded GC root.
pub fn GCAnalysis::root_path(
  self : GCAnalysis,
  target : UInt64,
) -> GCRootPath raise ParseError {
  if !self.is_reachable(target) {
    raise Invalid(0, "target is not strongly reachable from a GC root")
  }
  let queue = self.roots.copy()
  let discovered : Map[UInt64, Bool] = Map([])
  let origin : Map[UInt64, UInt64] = Map([])
  let parent : Map[UInt64, ReferenceEdge] = Map([])
  for root in self.roots {
    discovered[root] = true
    origin[root] = root
  }
  if discovered.contains(target) {
    return { root_id: target, edges: [], }
  }
  let mut cursor = 0
  while cursor < queue.length() {
    let id = queue[cursor]
    cursor += 1
    for edge in self.index.outbound.get(id).unwrap_or([]) {
      if !self.weak_reference_labels.contains(edge.label) &&
        !discovered.contains(edge.target_id) &&
        self.index.known_nodes.contains(edge.target_id) {
        discovered[edge.target_id] = true
        origin[edge.target_id] = origin[id]
        parent[edge.target_id] = edge
        queue.push(edge.target_id)
        if edge.target_id == target {
          let edges = []
          let mut current = target
          while parent.contains(current) {
            let incoming = parent[current]
            edges.push(incoming)
            current = incoming.source_id
          }
          edges.rev_in_place()
          return { root_id: origin[target], edges, }
        }
      }
    }
  }
  raise Invalid(0, "reachable target has no strong GC-root path")
}

///|
pub fn GCRootPath::to_json(self : GCRootPath) -> Json {
  Json::object({
    "root_id": json_id(self.root_id),
    "edges": Json::array(self.edges.map(edge => edge.to_json())),
  })
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
