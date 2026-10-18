///|
pub fn Summary::string(self : Summary, id : UInt64) -> String? {
  self.strings.get(id)
}

///|
pub fn Summary::class_name(self : Summary, id : UInt64) -> String? {
  match self.class_names.get(id) {
    Some(name) => self.strings.get(name)
    None => None
  }
}

///|
pub fn Summary::class_info(self : Summary, id : UInt64) -> ClassInfo? {
  self.definitions.get(id)
}

///|
pub fn Summary::object(self : Summary, id : UInt64) -> ObjectInfo? {
  self.objects.get(id)
}

///|
pub fn Summary::contains_object(self : Summary, id : UInt64) -> Bool {
  self.objects.contains(id) || self.definitions.contains(id)
}

///|
pub fn Summary::object_count(self : Summary) -> Int {
  self.objects.length() + self.definitions.length()
}

///|
pub fn Summary::file_size(self : Summary) -> Int {
  self.data.length()
}

///|
pub fn Summary::record_count(self : Summary, tag : Int) -> Int {
  self.record_counts.get(tag).unwrap_or(0)
}

///|
pub fn Summary::root_count(self : Summary) -> Int {
  self.roots_data.length()
}

///|
pub fn Summary::roots(
  self : Summary,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Array[RootInfo] raise ParseError {
  let end = page_end(offset, limit, self.roots_data.length())
  self.roots_data[offset:end].to_owned()
}

///|
fn page_end(offset : Int, limit : Int, length : Int) -> Int raise ParseError {
  if offset < 0 || offset > length || limit < 0 || limit > 100_000 {
    raise Invalid(offset, "invalid page (limit must be 0..100000)")
  }
  offset + (if limit < length - offset { limit } else { length - offset })
}

///|
pub fn Summary::class_ids(self : Summary) -> Array[UInt64] {
  let ids = self.definitions.keys().to_array()
  ids.sort()
  ids
}

///|
pub fn Summary::find_classes(self : Summary, name : String) -> Array[UInt64] {
  self.class_ids().filter(id => self.class_name(id) == Some(name))
}

///|
/// IDs are sorted numerically for stable pagination. Zero denotes all classes.
pub fn Summary::object_ids(
  self : Summary,
  class_id? : UInt64 = 0UL,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Array[UInt64] raise ParseError {
  let ids = []
  for id, object in self.objects {
    if class_id == 0UL || object.class_id == class_id {
      ids.push(id)
    }
  }
  ids.sort()
  let end = page_end(offset, limit, ids.length())
  ids[offset:end].to_owned()
}

///|
fn Summary::require_object(
  self : Summary,
  id : UInt64,
) -> ObjectInfo raise ParseError {
  match self.objects.get(id) {
    Some(info) => info
    None => raise Invalid(0, "object not found: \{id}")
  }
}

///|
/// Most-derived class first: HPROF writes fields before inherited fields.
pub fn Summary::hierarchy(
  self : Summary,
  class_id : UInt64,
) -> Array[ClassInfo] raise ParseError {
  let seen : Map[UInt64, Bool] = Map([])
  let result = []
  let mut current = class_id
  while current != 0UL {
    if seen.contains(current) {
      raise Invalid(0, "cyclic class hierarchy")
    }
    seen[current] = true
    let info = match self.definitions.get(current) {
      Some(value) => value
      None => raise Invalid(0, "missing class definition: \{current}")
    }
    result.push(info)
    current = info.superclass_id
  }
  result
}

///|
pub fn Summary::instance_fields(
  self : Summary,
  id : UInt64,
) -> Array[FieldValue] raise ParseError {
  let object = self.require_object(id)
  if object.kind != Instance {
    raise Invalid(0, "object is not an instance")
  }
  let r = Reader::{
    data: self.data,
    pos: object.payload_offset,
    end: object.payload_offset + object.payload_bytes,
    id_size: self.id_size,
  }
  let result = []
  for cls in self.hierarchy(object.class_id) {
    for field in cls.fields {
      let name = match self.strings.get(field.name_id) {
        Some(name) => name
        None => raise Invalid(r.pos, "missing field name")
      }
      result.push({
        declaring_class_id: cls.id,
        name,
        value: r.value(field.kind),
      })
    }
  }
  if r.pos != r.end {
    raise Invalid(r.pos, "instance payload does not match class layout")
  }
  result
}

///|
pub fn Summary::static_fields(
  self : Summary,
  class_id : UInt64,
) -> Array[FieldValue] raise ParseError {
  let cls = match self.class_info(class_id) {
    Some(cls) => cls
    None => raise Invalid(0, "class not found")
  }
  let result = []
  for field in cls.statics {
    let name = match self.string(field.name_id) {
      Some(name) => name
      None => raise Invalid(0, "missing static field name")
    }
    result.push({ declaring_class_id: class_id, name, value: field.value, })
  }
  result
}

///|
/// Returns typed array elements without materializing the complete array.
pub fn Summary::array_values(
  self : Summary,
  id : UInt64,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Array[Value] raise ParseError {
  let object = self.require_object(id)
  if object.kind == Instance {
    raise Invalid(0, "object is not an array")
  }
  let end = page_end(offset, limit, object.length)
  let kind = if object.kind == ObjectArray { 2 } else { object.primitive_kind }
  let width = type_width(kind, self.id_size)
  let r = Reader::{
    data: self.data,
    pos: object.payload_offset + offset * width,
    end: object.payload_offset + object.payload_bytes,
    id_size: self.id_size,
  }
  let result = []
  for _ in offset..<end {
    result.push(r.value(kind))
  }
  result
}

///|
pub fn Summary::stack_frame(self : Summary, id : UInt64) -> ResolvedFrame? {
  let frame = match self.frames.get(id) {
    Some(frame) => frame
    None => return None
  }
  let class_name = match self.class_serials.get(frame.class_serial) {
    Some(id) => self.class_name(id).unwrap_or("<unknown>")
    None => "<unknown>"
  }
  Some({
    id,
    class_name,
    method_name: self.string(frame.method_name_id).unwrap_or("<unknown>"),
    signature: self.string(frame.signature_id).unwrap_or("<unknown>"),
    source_name: self.string(frame.source_name_id).unwrap_or("<unknown>"),
    line_number: frame.line_number,
  })
}

///|
pub fn Summary::stack_trace(
  self : Summary,
  serial : UInt64,
) -> Array[ResolvedFrame] raise ParseError {
  let trace = match self.traces.get(serial) {
    Some(trace) => trace
    None => raise Invalid(0, "stack trace not found")
  }
  let result = []
  for id in trace.frame_ids {
    match self.stack_frame(id) {
      Some(frame) => result.push(frame)
      None => raise Invalid(0, "missing stack frame")
    }
  }
  result
}

///|
pub fn Summary::thread(self : Summary, serial : UInt64) -> ThreadInfo? {
  self.threads.get(serial)
}

///|
/// Field and array edges only. Null references are omitted.
pub fn Summary::references(
  self : Summary,
  id : UInt64,
  limit? : Int = 100,
) -> Array[ReferenceEdge] raise ParseError {
  if limit < 0 || limit > 100_000 {
    raise Invalid(0, "invalid reference limit")
  }
  let edges : Array[ReferenceEdge] = []
  if self.definitions.contains(id) {
    for field in self.static_fields(id) {
      if edges.length() >= limit {
        break
      }
      if field.value.reference() is Some(target) && target != 0UL {
        edges.push({ source_id: id, target_id: target, label: field.name, })
      }
    }
    return edges
  }
  let object = self.require_object(id)
  match object.kind {
    Instance =>
      for field in self.instance_fields(id) {
        if edges.length() >= limit {
          break
        }
        if field.value.reference() is Some(target) && target != 0UL {
          edges.push({ source_id: id, target_id: target, label: field.name, })
        }
      }
    ObjectArray => {
      // A limit bounds inspected elements as well as output edges.
      let values = self.array_values(id, limit~)
      for i in 0..<values.length() {
        if values[i].reference() is Some(target) && target != 0UL {
          edges.push({ source_id: id, target_id: target, label: "[\{i}]", })
        }
      }
    }
    PrimitiveArray => ()
  }
  edges
}

///|
pub fn Summary::histogram(
  self : Summary,
) -> Array[HistogramRow] raise ParseError {
  let rows : Map[String, HistogramRow] = Map([])
  for _, object in self.objects {
    let primitive = object.kind == PrimitiveArray
    let key = if primitive {
      "P\{object.primitive_kind}"
    } else {
      "C\{object.class_id}"
    }
    let name = if primitive {
      value_type_name(object.primitive_kind) + "[]"
    } else {
      self.class_name(object.class_id).unwrap_or("<unknown>")
    }
    let loader_id = match self.class_info(object.class_id) {
      Some(cls) => cls.loader_id
      None => 0UL
    }
    let old = rows.get(key)
    rows[key] = {
      name,
      class_id: object.class_id,
      loader_id,
      kind: object.kind.label(),
      count: old.map(row => row.count).unwrap_or(0) + 1,
      payload_bytes: old.map(row => row.payload_bytes).unwrap_or(0L) +
      object.payload_bytes.to_int64(),
      elements: old.map(row => row.elements).unwrap_or(0L) +
      object.length.to_int64(),
    }
  }
  let result = rows.values().to_array()
  result.sort_by((a, b) => {
    let count = b.count.compare(a.count)
    if count != 0 {
      count
    } else {
      let name = a.name.compare(b.name)
      if name != 0 {
        name
      } else {
        a.class_id.compare(b.class_id)
      }
    }
  })
  result
}
