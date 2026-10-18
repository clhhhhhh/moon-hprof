///|
pub struct MethodSignature {
  parameters : Array[String]
  return_type : String
  parameter_slots : Int
}

///|
fn descriptor_type(
  chars : Array[Char],
  start : Int,
  allow_void : Bool,
) -> (String, Int, Int) raise ParseError {
  let mut pos = start
  let mut dimensions = 0
  while pos < chars.length() && chars[pos] == '[' {
    dimensions += 1
    pos += 1
    if dimensions > 255 {
      raise Invalid(pos, "array descriptor exceeds 255 dimensions")
    }
  }
  if pos >= chars.length() {
    raise Invalid(pos, "missing descriptor component type")
  }
  let tag = chars[pos]
  pos += 1
  let (name, slots) = match tag {
    'Z' => ("boolean", 1)
    'B' => ("byte", 1)
    'C' => ("char", 1)
    'S' => ("short", 1)
    'I' => ("int", 1)
    'J' => ("long", 2)
    'F' => ("float", 1)
    'D' => ("double", 2)
    'V' if allow_void && dimensions == 0 => ("void", 0)
    'L' => {
      let begin = pos
      while pos < chars.length() && chars[pos] != ';' {
        if ['[', '.', '(', ')', ':', ' ', '\u0000'].contains(chars[pos]) {
          raise Invalid(pos, "invalid character in class descriptor")
        }
        pos += 1
      }
      if pos >= chars.length() || pos == begin {
        raise Invalid(pos, "unterminated or empty object descriptor")
      }
      let name = String::from_array(chars[begin:pos]).replace_all(
        old="/",
        new=".",
      )
      pos += 1
      (name, 1)
    }
    _ => raise Invalid(pos - 1, "invalid descriptor type")
  }
  (name + "[]".repeat(dimensions), pos, if dimensions > 0 { 1 } else { slots })
}

///|
/// Formats a field descriptor; void and trailing garbage are invalid.
pub fn field_descriptor(text : String) -> String raise ParseError {
  let chars = text.to_array()
  let (name, end, _) = descriptor_type(chars, 0, false)
  if end != chars.length() {
    raise Invalid(end, "trailing field descriptor data")
  }
  name
}

///|
/// Parses JVM method descriptors, excluding generic Signature attributes.
pub fn method_descriptor(text : String) -> MethodSignature raise ParseError {
  let chars = text.to_array()
  if chars.is_empty() || chars[0] != '(' {
    raise Invalid(0, "expected method descriptor")
  }
  let parameters = []
  let mut slots = 0
  let mut pos = 1
  while pos < chars.length() && chars[pos] != ')' {
    let (name, end, width) = descriptor_type(chars, pos, false)
    slots += width
    if slots > 255 {
      raise Invalid(pos, "method parameter slots exceed 255")
    }
    parameters.push(name)
    pos = end
  }
  if pos >= chars.length() {
    raise Invalid(pos, "missing method close parenthesis")
  }
  let (return_type, end, _) = descriptor_type(chars, pos + 1, true)
  if end != chars.length() {
    raise Invalid(end, "trailing method descriptor data")
  }
  { parameters, return_type, parameter_slots: slots, }
}

///|
pub fn MethodSignature::display(self : MethodSignature) -> String {
  "(" + self.parameters.join(", ") + ") -> " + self.return_type
}

///|
pub fn ResolvedFrame::readable_signature(
  self : ResolvedFrame,
) -> String raise ParseError {
  self.method_name + method_descriptor(self.signature).display()
}
