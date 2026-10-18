///|
fn utf16_text(units : Array[Int]) -> String raise ParseError {
  let builder = StringBuilder()
  let mut i = 0
  while i < units.length() {
    let mut value = units[i]
    i += 1
    if value >= 0xd800 && value <= 0xdbff {
      if i >= units.length() || units[i] < 0xdc00 || units[i] > 0xdfff {
        raise Invalid(i - 1, "unpaired high surrogate in Java String")
      }
      value = 0x10000 + ((value - 0xd800) << 10) + units[i] - 0xdc00
      i += 1
    } else if value >= 0xdc00 && value <= 0xdfff {
      raise Invalid(i - 1, "unpaired low surrogate in Java String")
    }
    match value.to_char() {
      Some(char) => builder.write_char(char)
      None => raise Invalid(i - 1, "invalid character in Java String")
    }
  }
  builder.to_string()
}

///|
/// Reads JDK char[] Strings and compact byte[] Strings with explicit byte order.
/// HPROF does not encode the native byte order of compact UTF-16 String storage.
pub fn Summary::java_string(
  self : Summary,
  id : UInt64,
  utf16_little_endian~ : Bool,
  max_chars? : Int = 4096,
) -> String raise ParseError {
  if max_chars < 0 || max_chars > 100_000 {
    raise Invalid(0, "invalid String character limit")
  }
  let object = self.require_object(id)
  if object.kind != Instance ||
    self.class_name(object.class_id) != Some("java/lang/String") {
    raise Invalid(0, "object is not a java/lang/String")
  }
  let array_id = match self.field(id, "value") {
    Some(Reference(value)) if value != 0UL => value
    _ => raise Invalid(0, "missing Java String backing array")
  }
  let array = self.require_object(array_id)
  if array.kind != PrimitiveArray {
    raise Invalid(0, "invalid String backing array kind")
  }
  if array.primitive_kind == 5 {
    let offset = match self.field(id, "offset") {
      Some(IntValue(n)) => n
      None => 0
      _ => raise Invalid(0, "invalid legacy String offset")
    }
    let count = match self.field(id, "count") {
      Some(IntValue(n)) => n
      None => array.length - offset
      _ => raise Invalid(0, "invalid legacy String count")
    }
    if count < 0 ||
      count > max_chars ||
      offset < 0 ||
      offset > array.length ||
      count > array.length - offset {
      raise Invalid(0, "legacy String slice exceeds backing array or limit")
    }
    let units = []
    for value in self.array_values(array_id, offset~, limit=count) {
      match value {
        Character(unit) => units.push(unit)
        _ => raise Invalid(0, "invalid character backing array")
      }
    }
    return utf16_text(units)
  }
  if array.primitive_kind != 8 {
    raise Invalid(0, "unsupported String backing array element type")
  }
  let coder = match self.field(id, "coder") {
    Some(ByteValue(n)) => n
    _ => raise Invalid(0, "missing compact String coder")
  }
  let units = []
  let start = array.payload_offset
  match coder {
    0 => {
      if array.length > max_chars {
        raise Invalid(start, "String exceeds character limit")
      }
      for i in 0..<array.length {
        units.push(self.data[start + i].to_int())
      }
    }
    1 => {
      if array.length % 2 != 0 || array.length / 2 > max_chars {
        raise Invalid(start, "invalid compact UTF-16 length or character limit")
      }
      for i in 0..<(array.length / 2) {
        let a = self.data[start + i * 2].to_int()
        let b = self.data[start + i * 2 + 1].to_int()
        units.push(
          if utf16_little_endian {
            a | (b << 8)
          } else {
            (a << 8) | b
          },
        )
      }
    }
    _ => raise Invalid(start, "unknown compact String coder")
  }
  utf16_text(units)
}
