///|
pub struct ObjectPreview {
  id : UInt64
  kind : String
  class_name : String
  payload_bytes : Int
  array_length : Int?
  text : String
  truncated : Bool
}

///|
pub fn Value::display(self : Value) -> String {
  match self {
    Reference(0UL) => "null"
    Reference(id) => "@" + id.to_string(radix=16)
    Boolean(value) => if value { "true" } else { "false" }
    Character(value) =>
      // A Java char can contain an isolated surrogate, so keep its numeric form.
      "U+" + value.to_string(radix=16)
    ByteValue(value) | ShortValue(value) | IntValue(value) => value.to_string()
    LongValue(value) => value.to_string() + "L"
    FloatValue(value) => value.to_string() + "f"
    DoubleValue(value) => value.to_string()
  }
}

///|
fn preview_prefix(text : String, maximum : Int) -> (String, Bool) {
  let chars = text.to_array()
  if chars.length() <= maximum {
    return (text, false)
  }
  (String::from_array(chars[0:maximum]), true)
}

///|
/// A one-level display: referenced objects are IDs and never recursively opened.
pub fn Summary::preview(
  self : Summary,
  id : UInt64,
  max_items? : Int = 8,
  max_chars? : Int = 256,
) -> ObjectPreview raise ParseError {
  if max_items < 0 ||
    max_items > 100_000 ||
    max_chars < 0 ||
    max_chars > 100_000 {
    raise Invalid(0, "invalid preview limits")
  }
  if self.definitions.contains(id) {
    let name = self.class_name(id).unwrap_or("<unknown>")
    let (text, clipped) = preview_prefix(
      "class " + display_class_name(name),
      max_chars,
    )
    return {
      id,
      kind: "class",
      class_name: name,
      payload_bytes: 0,
      array_length: None,
      text,
      truncated: clipped,
    }
  }
  let object = self.require_object(id)
  let class_name = if object.kind == PrimitiveArray {
    value_type_name(object.primitive_kind) + "[]"
  } else {
    self.class_name(object.class_id).unwrap_or("<unknown>")
  }
  let builder = StringBuilder()
  let mut omitted = false
  let length = match object.kind {
    Instance => {
      builder.write_string(display_class_name(class_name) + "{")
      let fields = self.instance_fields(id)
      let count = if fields.length() < max_items {
        fields.length()
      } else {
        max_items
      }
      for i in 0..<count {
        if i > 0 {
          builder.write_string(", ")
        }
        builder.write_string(fields[i].name + "=" + fields[i].value.display())
      }
      omitted = count < fields.length()
      if omitted {
        builder.write_string(", ...")
      }
      builder.write_string("}")
      None
    }
    ObjectArray | PrimitiveArray => {
      builder.write_string(display_class_name(class_name) + "[")
      let values = self.array_values(id, limit=max_items)
      for i in 0..<values.length() {
        if i > 0 {
          builder.write_string(", ")
        }
        builder.write_string(values[i].display())
      }
      omitted = values.length() < object.length
      if omitted {
        builder.write_string(", ...")
      }
      builder.write_string("]")
      Some(object.length)
    }
  }
  let (text, clipped) = preview_prefix(builder.to_string(), max_chars)
  {
    id,
    kind: object.kind.label(),
    class_name,
    payload_bytes: object.payload_bytes,
    array_length: length,
    text,
    truncated: omitted || clipped,
  }
}

///|
pub fn ObjectPreview::to_json(self : ObjectPreview) -> Json {
  Json::object({
    "id": json_id(self.id),
    "kind": Json::string(self.kind),
    "class_name": Json::string(self.class_name),
    "payload_bytes": json_int(self.payload_bytes),
    "array_length": self.array_length.map(json_int).unwrap_or(Json::null()),
    "text": Json::string(self.text),
    "truncated": Json::boolean(self.truncated),
  })
}

///|
/// Exports a bounded page as JSON Lines; each object is a separate JSON document.
/// Arrays use their own item limit rather than expanding arbitrary-size payloads.
pub fn Summary::objects_jsonl(
  self : Summary,
  class_id? : UInt64 = 0UL,
  offset? : Int = 0,
  limit? : Int = 100,
  array_limit? : Int = 20,
) -> String raise ParseError {
  if array_limit < 0 || array_limit > 100_000 {
    raise Invalid(0, "invalid array export limit")
  }
  let builder = StringBuilder()
  for id in self.object_ids(class_id~, offset~, limit~) {
    builder.write_string(self.object_json(id, limit=array_limit).stringify())
    builder.write_string("\n")
  }
  builder.to_string()
}

///|
pub fn Summary::previews_jsonl(
  self : Summary,
  class_id? : UInt64 = 0UL,
  offset? : Int = 0,
  limit? : Int = 100,
  max_items? : Int = 8,
  max_chars? : Int = 256,
) -> String raise ParseError {
  if max_items < 0 ||
    max_items > 100_000 ||
    max_chars < 0 ||
    max_chars > 100_000 {
    raise Invalid(0, "invalid preview export limits")
  }
  let builder = StringBuilder()
  for id in self.object_ids(class_id~, offset~, limit~) {
    builder.write_string(
      self.preview(id, max_items~, max_chars~).to_json().stringify(),
    )
    builder.write_string("\n")
  }
  builder.to_string()
}
