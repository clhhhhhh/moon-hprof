///|
/// Decodes Java Modified UTF-8, also accepting canonical four-byte UTF-8.
/// Unlike lossy decoding, invalid sequences never silently change identifiers.
pub fn decode_hprof_text(data : Bytes) -> String raise ParseError {
  let units : Array[Int] = []
  let mut pos = 0
  while pos < data.length() {
    let offset = pos
    let first = data[pos].to_int()
    pos += 1
    if first < 128 {
      units.push(first)
      continue
    }
    let count = if first >= 0xc0 && first <= 0xdf {
      1
    } else if first >= 0xe0 && first <= 0xef {
      2
    } else if first >= 0xf0 && first <= 0xf4 {
      3
    } else {
      raise Invalid(offset, "invalid UTF-8 leading byte")
    }
    if count > data.length() - pos {
      raise Invalid(offset, "truncated UTF-8")
    }
    let mut value = first &
      (if count == 1 { 31 } else if count == 2 { 15 } else { 7 })
    for _ in 0..<count {
      let next = data[pos].to_int()
      if next < 128 || next > 191 {
        raise Invalid(pos, "invalid UTF-8 continuation")
      }
      pos += 1
      value = (value << 6) | (next & 63)
    }
    if (count == 1 && value < 128 && value != 0) ||
      (count == 2 && value < 2048) ||
      (count == 3 && (value < 65536 || value > 0x10ffff)) {
      raise Invalid(offset, "overlong or out-of-range UTF-8")
    }
    units.push(value)
  }
  let out = StringBuilder()
  let mut i = 0
  while i < units.length() {
    let mut value = units[i]
    i += 1
    if value >= 0xd800 && value <= 0xdbff {
      if i >= units.length() || units[i] < 0xdc00 || units[i] > 0xdfff {
        raise Invalid(i - 1, "unpaired UTF-16 high surrogate")
      }
      value = 0x10000 + ((value - 0xd800) << 10) + units[i] - 0xdc00
      i += 1
    } else if value >= 0xdc00 && value <= 0xdfff {
      raise Invalid(i - 1, "unpaired UTF-16 low surrogate")
    }
    match value.to_char() {
      Some(char) => out.write_char(char)
      None => raise Invalid(i - 1, "invalid Unicode scalar")
    }
  }
  out.to_string()
}

///|
/// Converts a JVM array descriptor to a display name without changing identity.
pub fn display_class_name(name : String) -> String {
  let chars = name.to_array()
  let mut dimensions = 0
  while dimensions < chars.length() && chars[dimensions] == '[' {
    dimensions += 1
  }
  if dimensions == 0 {
    return name.replace_all(old="/", new=".")
  }
  let body = String::from_array(chars[dimensions:])
  let component = match body {
    "Z" => "boolean"
    "B" => "byte"
    "C" => "char"
    "S" => "short"
    "I" => "int"
    "J" => "long"
    "F" => "float"
    "D" => "double"
    _ =>
      if body.has_prefix("L") && body.has_suffix(";") {
        String::from_array(chars[dimensions + 1:chars.length() - 1]).replace_all(
          old="/",
          new=".",
        )
      } else {
        return name
      }
  }
  component + "[]".repeat(dimensions)
}

///|
/// RFC 4180 cell escaping. Newlines inside cells remain quoted data.
pub fn csv_cell(value : String) -> String {
  if value.contains(",") ||
    value.contains("\"") ||
    value.contains("\r") ||
    value.contains("\n") {
    "\"" + value.replace_all(old="\"", new="\"\"") + "\""
  } else {
    value
  }
}

///|
fn encode_unit(units : Array[Byte], value : Int) -> Unit {
  if value > 0 && value < 128 {
    units.push(value.to_byte())
  } else if value < 2048 {
    units.push((0xc0 | (value >> 6)).to_byte())
    units.push((0x80 | (value & 63)).to_byte())
  } else {
    units.push((0xe0 | (value >> 12)).to_byte())
    units.push((0x80 | ((value >> 6) & 63)).to_byte())
    units.push((0x80 | (value & 63)).to_byte())
  }
}

///|
/// Encodes Java Modified UTF-8, including two-byte NUL and surrogate pairs.
pub fn encode_hprof_text(text : String) -> Bytes {
  let units = []
  for char in text {
    let value = char.to_int()
    if value > 65535 {
      encode_unit(units, 0xd800 + ((value - 0x10000) >> 10))
      encode_unit(units, 0xdc00 + ((value - 0x10000) & 1023))
    } else {
      encode_unit(units, value)
    }
  }
  Bytes::from_array(units)
}
