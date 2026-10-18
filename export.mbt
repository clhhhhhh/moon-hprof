///|
fn json_id(id : UInt64) -> Json {
  // Decimal strings preserve object IDs beyond JavaScript's 53-bit range.
  Json::string(id.to_string())
}

///|
pub fn Value::to_json(self : Value) -> Json {
  let value = match self {
    Reference(id) => json_id(id)
    Boolean(value) => Json::boolean(value)
    Character(value) | ByteValue(value) | ShortValue(value) | IntValue(value) =>
      value.to_json()
    LongValue(value) => Json::string(value.to_string())
    FloatValue(value) | DoubleValue(value) =>
      // NaN/Infinity have no JSON numeric representation.
      if value.is_nan() {
        Json::string("NaN")
      } else if value.is_pos_inf() {
        Json::string("Infinity")
      } else if value.is_neg_inf() {
        Json::string("-Infinity")
      } else {
        Json::number(value)
      }
  }
  Json::object({
    "type": Json::string(value_type_name(self.kind()) catch { _ => "unknown" }),
    "value": value,
  })
}

///|
pub fn Summary::summary_json(self : Summary) -> Json {
  Json::object({
    "format": Json::string("JAVA PROFILE 1.0.2"),
    "id_size": self.id_size.to_json(),
    "timestamp_ms": json_id(self.timestamp_ms),
    "file_bytes": self.file_size().to_json(),
    "classes": self.classes.to_json(),
    "instances": self.instances.to_json(),
    "object_arrays": self.object_arrays.to_json(),
    "primitive_arrays": self.primitive_arrays.to_json(),
    "roots": self.root_count().to_json(),
    "stack_frames": self.frames.length().to_json(),
    "stack_traces": self.traces.length().to_json(),
  })
}

///|
pub fn HistogramRow::to_json(self : HistogramRow) -> Json {
  Json::object({
    "name": Json::string(self.name),
    "display_name": Json::string(display_class_name(self.name)),
    "class_id": json_id(self.class_id),
    "loader_id": json_id(self.loader_id),
    "kind": Json::string(self.kind),
    "count": self.count.to_json(),
    "payload_bytes": Json::string(self.payload_bytes.to_string()),
    "elements": Json::string(self.elements.to_string()),
  })
}

///|
pub fn Summary::histogram_json(self : Summary) -> Json raise ParseError {
  Json::array(self.histogram().map(row => row.to_json()))
}

///|
pub fn Summary::histogram_csv(self : Summary) -> String raise ParseError {
  let out = StringBuilder()
  out.write_string(
    "name,class_id,loader_id,kind,count,payload_bytes,elements\r\n",
  )
  for row in self.histogram() {
    let cells = [
      row.name,
      row.class_id.to_string(),
      row.loader_id.to_string(),
      row.kind,
      row.count.to_string(),
      row.payload_bytes.to_string(),
      row.elements.to_string(),
    ]
    out.write_string(cells.map(csv_cell).join(","))
    out.write_string("\r\n")
  }
  out.to_string()
}

///|
fn field_json(field : FieldValue) -> Json {
  Json::object({
    "declaring_class_id": json_id(field.declaring_class_id),
    "name": Json::string(field.name),
    "value": field.value.to_json(),
  })
}

///|
pub fn Summary::class_json(
  self : Summary,
  id : UInt64,
) -> Json raise ParseError {
  let cls = match self.class_info(id) {
    Some(cls) => cls
    None => raise Invalid(0, "class not found")
  }
  let fields = cls.fields.map(field => {
    Json::object({
      "name": Json::string(self.string(field.name_id).unwrap_or("<unknown>")),
      "type": Json::string(value_type_name(field.kind) catch { _ => "unknown" }),
    })
  })
  let constants = cls.constants.map(entry => {
    Json::object({
      "index": entry.index.to_json(),
      "value": entry.value.to_json(),
    })
  })
  Json::object({
    "id": json_id(id),
    "name": Json::string(self.class_name(id).unwrap_or("<unknown>")),
    "superclass_id": json_id(cls.superclass_id),
    "loader_id": json_id(cls.loader_id),
    "signers_id": json_id(cls.signers_id),
    "protection_domain_id": json_id(cls.protection_domain_id),
    "reported_instance_size": cls.instance_size.to_json(),
    "fields": Json::array(fields),
    "statics": Json::array(self.static_fields(id).map(field_json)),
    "constants": Json::array(constants),
  })
}

///|
/// Exports one object; array pages include total length and requested offset.
pub fn Summary::object_json(
  self : Summary,
  id : UInt64,
  offset? : Int = 0,
  limit? : Int = 100,
) -> Json raise ParseError {
  if self.definitions.contains(id) {
    return self.class_json(id)
  }
  let object = self.require_object(id)
  let fields : Map[String, Json] = {
    "id": json_id(id),
    "kind": Json::string(object.kind.label()),
    "class_id": json_id(object.class_id),
    "stack_serial": json_id(object.stack_serial),
    "payload_bytes": object.payload_bytes.to_json(),
    "payload_offset": object.payload_offset.to_json(),
  }
  match object.kind {
    Instance => {
      fields["class_name"] = Json::string(
        self.class_name(object.class_id).unwrap_or("<unknown>"),
      )
      fields["fields"] = Json::array(self.instance_fields(id).map(field_json))
    }
    ObjectArray | PrimitiveArray => {
      fields["length"] = object.length.to_json()
      fields["offset"] = offset.to_json()
      fields["values"] = Json::array(
        self.array_values(id, offset~, limit~).map(value => value.to_json()),
      )
      if object.kind == PrimitiveArray {
        fields["element_type"] = Json::string(
          value_type_name(object.primitive_kind),
        )
      }
    }
  }
  Json::object(fields)
}

///|
pub fn RootInfo::to_json(self : RootInfo) -> Json {
  Json::object({
    "kind": Json::string(self.label()),
    "object_id": json_id(self.object_id),
    "related_id": json_id(self.related_id),
    "thread_serial": json_id(self.thread_serial),
    "frame_number": json_id(self.frame_number),
  })
}

///|
pub fn ReferenceEdge::to_json(self : ReferenceEdge) -> Json {
  Json::object({
    "source_id": json_id(self.source_id),
    "target_id": json_id(self.target_id),
    "label": Json::string(self.label),
  })
}

///|
pub fn ResolvedFrame::to_json(self : ResolvedFrame) -> Json {
  Json::object({
    "id": json_id(self.id),
    "class_name": Json::string(self.class_name),
    "method_name": Json::string(self.method_name),
    "signature": Json::string(self.signature),
    "source_name": Json::string(self.source_name),
    "line_number": self.line_number.to_json(),
  })
}
