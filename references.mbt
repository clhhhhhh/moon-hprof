///|
/// Reusable bidirectional index of recorded object references.
pub struct ReferenceIndex {
  priv inbound : Map[UInt64, Array[ReferenceEdge]]
  priv outbound : Map[UInt64, Array[ReferenceEdge]]
  priv known_nodes : Map[UInt64, Bool]
  priv mut slots : Int
  priv mut edges : Int
}

///|
fn ReferenceIndex::add(
  self : ReferenceIndex,
  source : UInt64,
  target : UInt64,
  label : String,
  max_edges : Int,
  max_slots : Int,
) -> Unit raise ParseError {
  check_limit(0, "reference slots", self.slots, max_slots)
  self.slots += 1
  if target == 0UL {
    return
  }
  check_limit(0, "reference edges", self.edges, max_edges)
  let edge = ReferenceEdge::{ source_id: source, target_id: target, label, }
  let incoming = self.inbound.get(target).unwrap_or([])
  incoming.push(edge)
  self.inbound[target] = incoming
  let outgoing = self.outbound.get(source).unwrap_or([])
  outgoing.push(edge)
  self.outbound[source] = outgoing
  self.edges += 1
}

///|
/// Builds once for repeated inbound/outbound queries. Exhausted budgets fail
/// explicitly instead of returning an incomplete index that appears complete.
pub fn ReferenceIndex::build(
  heap : Summary,
  max_edges? : Int = 1_000_000,
  max_slots? : Int = 10_000_000,
) -> ReferenceIndex raise ParseError {
  if max_edges < 0 || max_slots < 0 {
    raise Invalid(0, "reference index budgets cannot be negative")
  }
  let index = ReferenceIndex::{
    inbound: {},
    outbound: {},
    known_nodes: {},
    slots: 0,
    edges: 0,
  }
  let ids = heap.objects.keys().to_array()
  ids.append(heap.class_ids())
  ids.sort()
  for id in ids {
    index.known_nodes[id] = true
    if heap.definitions.contains(id) {
      let cls = heap.definitions[id]
      index.add(id, cls.superclass_id, "superclass", max_edges, max_slots)
      index.add(id, cls.loader_id, "class_loader", max_edges, max_slots)
      index.add(id, cls.signers_id, "signers", max_edges, max_slots)
      index.add(
        id,
        cls.protection_domain_id,
        "protection_domain",
        max_edges,
        max_slots,
      )
      for constant in cls.constants {
        if constant.value.reference() is Some(target) {
          index.add(
            id, target, "constant_pool[{constant.index}]", max_edges, max_slots,
          )
        }
      }
      for field in heap.static_fields(id) {
        if field.value.reference() is Some(target) {
          index.add(id, target, field.name, max_edges, max_slots)
        }
      }
      continue
    }
    let object = heap.require_object(id)
    match object.kind {
      Instance => {
        index.add(id, object.class_id, "@class", max_edges, max_slots)
        for field in heap.instance_fields(id) {
          if field.value.reference() is Some(target) {
            // The declaring class distinguishes shadowed field names.
            index.add(
              id,
              target,
              "\{field.declaring_class_id}:\{field.name}",
              max_edges,
              max_slots,
            )
          }
        }
      }
      ObjectArray => {
        index.add(id, object.class_id, "@class", max_edges, max_slots)
        if object.length > max_slots - index.slots {
          raise Invalid(
            object.payload_offset,
            "reference slot budget exceeded by array",
          )
        }
        let reader = Reader::{
          data: heap.data,
          pos: object.payload_offset,
          end: object.payload_offset + object.payload_bytes,
          id_size: heap.id_size,
        }
        for position in 0..<object.length {
          index.add(id, reader.id(), "[\{position}]", max_edges, max_slots)
        }
      }
      PrimitiveArray => ()
    }
  }
  index
}

///|
pub fn ReferenceIndex::edge_count(self : ReferenceIndex) -> Int {
  self.edges
}

///|
pub fn ReferenceIndex::slot_count(self : ReferenceIndex) -> Int {
  self.slots
}

///|
pub fn ReferenceIndex::incoming(
  self : ReferenceIndex,
  id : UInt64,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Array[ReferenceEdge] raise ParseError {
  let edges = self.inbound.get(id).unwrap_or([])
  let end = page_end(offset, limit, edges.length())
  edges[offset:end].to_owned()
}

///|
pub fn ReferenceIndex::outgoing(
  self : ReferenceIndex,
  id : UInt64,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Array[ReferenceEdge] raise ParseError {
  let edges = self.outbound.get(id).unwrap_or([])
  let end = page_end(offset, limit, edges.length())
  edges[offset:end].to_owned()
}

///|
pub struct ReferencePath {
  found : Bool
  truncated : Bool
  visited_nodes : Int
  inspected_edges : Int
  edges : Array[ReferenceEdge]
}

///|
/// Bounded breadth-first search, reporting truncation separately from no path.
/// Search only follows the indexed edge kinds, not VM/class-loader metadata.
pub fn ReferenceIndex::path(
  self : ReferenceIndex,
  source : UInt64,
  target : UInt64,
  max_depth? : Int = 8,
  max_nodes? : Int = 10_000,
  max_edges? : Int = 100_000,
) -> ReferencePath raise ParseError {
  if max_depth < 0 || max_nodes < 1 || max_edges < 0 {
    raise Invalid(0, "invalid reference path search budget")
  }
  if !self.known_nodes.contains(source) ||
    (!self.known_nodes.contains(target) && !self.inbound.contains(target)) {
    raise Invalid(0, "path endpoint is not present in the indexed graph")
  }
  if source == target {
    return {
      found: true,
      truncated: false,
      visited_nodes: 1,
      inspected_edges: 0,
      edges: [],
    }
  }
  let queue = [source]
  let depths : Map[UInt64, Int] = Map([(source, 0)])
  let parents : Map[UInt64, ReferenceEdge] = Map([])
  let mut cursor = 0
  let mut inspected = 0
  let mut truncated = false
  while cursor < queue.length() {
    let node = queue[cursor]
    cursor += 1
    let depth = depths[node]
    let outgoing = self.outbound.get(node).unwrap_or([])
    if depth >= max_depth {
      if outgoing.any(edge => !depths.contains(edge.target_id)) {
        truncated = true
      }
      continue
    }
    for edge in outgoing {
      if inspected >= max_edges {
        return {
          found: false,
          truncated: true,
          visited_nodes: queue.length(),
          inspected_edges: inspected,
          edges: [],
        }
      }
      inspected += 1
      if depths.contains(edge.target_id) {
        continue
      }
      if queue.length() >= max_nodes {
        return {
          found: false,
          truncated: true,
          visited_nodes: queue.length(),
          inspected_edges: inspected,
          edges: [],
        }
      }
      depths[edge.target_id] = depth + 1
      parents[edge.target_id] = edge
      queue.push(edge.target_id)
      if edge.target_id == target {
        let result = []
        let mut current = target
        while current != source {
          let parent = parents[current]
          result.push(parent)
          current = parent.source_id
        }
        result.rev_in_place()
        return {
          found: true,
          truncated: false,
          visited_nodes: queue.length(),
          inspected_edges: inspected,
          edges: result,
        }
      }
    }
  }
  {
    found: false,
    truncated,
    visited_nodes: queue.length(),
    inspected_edges: inspected,
    edges: [],
  }
}

///|
pub fn ReferencePath::to_json(self : ReferencePath) -> Json {
  Json::object({
    "found": Json::boolean(self.found),
    "truncated": Json::boolean(self.truncated),
    "visited_nodes": json_int(self.visited_nodes),
    "inspected_edges": json_int(self.inspected_edges),
    "edges": Json::array(self.edges.map(edge => edge.to_json())),
  })
}
