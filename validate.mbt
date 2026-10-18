///|
/// Checks class layouts and metadata references. Does not infer object liveness.
pub fn Summary::validate(self : Summary) -> Unit raise ParseError {
  for id, cls in self.definitions {
    if self.class_name(id) is None {
      raise Invalid(0, "missing class name: \{id}")
    }
    ignore(self.hierarchy(id))
    for field in cls.fields {
      if self.string(field.name_id) is None {
        raise Invalid(0, "unresolved instance field name")
      }
    }
    for field in cls.statics {
      if self.string(field.name_id) is None {
        raise Invalid(0, "unresolved static field name")
      }
    }
  }
  for id, object in self.objects {
    match object.kind {
      Instance => ignore(self.instance_fields(id))
      ObjectArray =>
        if !self.definitions.contains(object.class_id) {
          raise Invalid(object.payload_offset, "missing object-array class")
        }
      PrimitiveArray =>
        // Only boolean payloads have bit patterns that are not valid values.
        if object.primitive_kind == 4 {
          let start = object.payload_offset
          for i in start..<(start + object.payload_bytes) {
            if self.data[i].to_int() > 1 {
              raise Invalid(i, "invalid boolean array element")
            }
          }
        }
    }
  }
  for _, trace in self.traces {
    for id in trace.frame_ids {
      if !self.frames.contains(id) {
        raise Invalid(0, "unresolved stack frame")
      }
    }
  }
}

///|
pub fn Summary::instance_payload_size(
  self : Summary,
  class_id : UInt64,
) -> Int raise ParseError {
  let mut result = 0
  for cls in self.hierarchy(class_id) {
    for field in cls.fields {
      let width = type_width(field.kind, self.id_size)
      if result > 2_147_483_647 - width {
        raise Invalid(0, "class layout too large")
      }
      result += width
    }
  }
  result
}

///|
/// Copies only the requested payload window; offsets are relative to payload.
pub fn Summary::payload(
  self : Summary,
  id : UInt64,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Bytes raise ParseError {
  let object = self.require_object(id)
  let end = page_end(offset, limit, object.payload_bytes)
  let start = object.payload_offset
  self.data[start + offset:start + end].to_owned()
}

///|
pub fn Summary::root_kinds(self : Summary) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for root in self.roots_data {
    let label = root.label()
    counts[label] = counts.get(label).unwrap_or(0) + 1
  }
  counts
}

///|
/// Returns all matching GC roots. Multiple roots may refer to one object.
pub fn Summary::roots_for(self : Summary, id : UInt64) -> Array[RootInfo] {
  self.roots_data.filter(root => root.object_id == id)
}

///|
pub fn Summary::thread_serials(self : Summary) -> Array[UInt64] {
  let serials = self.threads.keys().to_array()
  serials.sort()
  serials
}

///|
pub fn Summary::trace_serials(self : Summary) -> Array[UInt64] {
  let serials = self.traces.keys().to_array()
  serials.sort()
  serials
}

///|
pub fn Summary::field(
  self : Summary,
  id : UInt64,
  name : String,
  declaring_class? : UInt64 = 0UL,
) -> Value? raise ParseError {
  let fields = if self.definitions.contains(id) {
    self.static_fields(id)
  } else {
    self.instance_fields(id)
  }
  let matches = fields.filter(field => {
    field.name == name &&
    (declaring_class == 0UL || field.declaring_class_id == declaring_class)
  })
  if matches.length() > 1 {
    raise Invalid(0, "ambiguous field name; specify declaring class")
  }
  matches.get(0).map(field => field.value)
}
