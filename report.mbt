///|
pub enum HistogramSort {
  Count
  Payload
  Elements
  Name
}

///|
/// Filters by internal class name prefix and object kind before pagination.
pub fn Summary::select_histogram(
  self : Summary,
  prefix? : String = "",
  kind? : String = "",
  sort? : HistogramSort = Count,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Array[HistogramRow] raise ParseError {
  if kind != "" &&
    kind != "instance" &&
    kind != "object_array" &&
    kind != "primitive_array" {
    raise Invalid(0, "unknown histogram kind")
  }
  let rows = self
    .histogram()
    .filter(row => {
      row.name.has_prefix(prefix) && (kind == "" || kind == row.kind)
    })
  rows.sort_by((a, b) => {
    let primary = match sort {
      Count => b.count.compare(a.count)
      Payload => b.payload_bytes.compare(a.payload_bytes)
      Elements => b.elements.compare(a.elements)
      Name => a.name.compare(b.name)
    }
    if primary != 0 {
      primary
    } else {
      let name = a.name.compare(b.name)
      if name != 0 {
        name
      } else {
        a.class_id.compare(b.class_id)
      }
    }
  })
  let end = page_end(offset, limit, rows.length())
  rows[offset:end].to_owned()
}

///|
pub struct HeapTotals {
  class_objects : Int
  instance_objects : Int
  array_objects : Int
  payload_bytes : Int64
  array_elements : Int64
  largest_payload_id : UInt64
  largest_payload_bytes : Int
}

///|
pub fn Summary::totals(self : Summary) -> HeapTotals {
  let mut payload = 0L
  let mut elements = 0L
  let mut largest_id = 0UL
  let mut largest_size = -1
  for id, object in self.objects {
    payload += object.payload_bytes.to_int64()
    elements += object.length.to_int64()
    if object.payload_bytes > largest_size ||
      (object.payload_bytes == largest_size && id < largest_id) {
      largest_id = id
      largest_size = object.payload_bytes
    }
  }
  {
    class_objects: self.classes,
    instance_objects: self.instances,
    array_objects: self.object_arrays + self.primitive_arrays,
    payload_bytes: payload,
    array_elements: elements,
    largest_payload_id: largest_id,
    largest_payload_bytes: if largest_size < 0 {
      0
    } else {
      largest_size
    },
  }
}

///|
pub struct HistogramDelta {
  name : String
  kind : String
  before_count : Int
  after_count : Int
  count_delta : Int64
  payload_delta : Int64
}

///|
/// Compares class-name aggregates. Object/loader IDs are not stable across dumps.
/// This is a count comparison, not a claim that the same objects survived GC.
pub fn compare_heaps(
  before : Summary,
  after : Summary,
) -> Array[HistogramDelta] raise ParseError {
  let left : Map[(String, String), (Int, Int64)] = Map([])
  let right : Map[(String, String), (Int, Int64)] = Map([])
  let keys : Map[(String, String), Bool] = Map([])
  for pair in [(before, left), (after, right)] {
    for row in pair.0.histogram() {
      let key = (row.name, row.kind)
      let previous = pair.1.get(key).unwrap_or((0, 0L))
      pair.1[key] = (previous.0 + row.count, previous.1 + row.payload_bytes)
      keys[key] = true
    }
  }
  let rows = []
  for key, _ in keys {
    let a = left.get(key).unwrap_or((0, 0L))
    let b = right.get(key).unwrap_or((0, 0L))
    rows.push({
      name: key.0,
      kind: key.1,
      before_count: a.0,
      after_count: b.0,
      count_delta: b.0.to_int64() - a.0.to_int64(),
      payload_delta: b.1 - a.1,
    })
  }
  rows.sort_by((a, b) => {
    let name = a.name.compare(b.name)
    if name != 0 {
      name
    } else {
      a.kind.compare(b.kind)
    }
  })
  rows
}

///|
pub fn HistogramDelta::to_json(self : HistogramDelta) -> Json {
  Json::object({
    "name": Json::string(self.name),
    "kind": Json::string(self.kind),
    "before_count": self.before_count.to_json(),
    "after_count": self.after_count.to_json(),
    "count_delta": Json::string(self.count_delta.to_string()),
    "payload_delta": Json::string(self.payload_delta.to_string()),
  })
}

///|
pub fn Summary::largest_objects(
  self : Summary,
  limit? : Int = 20,
) -> Array[ObjectInfo] raise ParseError {
  let rows = self.objects.values().to_array()
  rows.sort_by((a, b) => {
    let size = b.payload_bytes.compare(a.payload_bytes)
    if size != 0 {
      size
    } else {
      a.id.compare(b.id)
    }
  })
  let end = page_end(0, limit, rows.length())
  rows[0:end].to_owned()
}
