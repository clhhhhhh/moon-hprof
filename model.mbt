///|
/// A typed HPROF value. Object IDs are kept as unsigned 64-bit integers.
pub enum Value {
  Reference(UInt64)
  Boolean(Bool)
  Character(Int)
  ByteValue(Int)
  ShortValue(Int)
  IntValue(Int)
  LongValue(Int64)
  FloatValue(Double)
  DoubleValue(Double)
} derive(Debug)

///|
pub extend Value with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn Value::reference(self : Value) -> UInt64? {
  match self {
    Reference(id) => Some(id)
    _ => None
  }
}

///|
pub fn Value::kind(self : Value) -> Int {
  match self {
    Reference(_) => 2
    Boolean(_) => 4
    Character(_) => 5
    FloatValue(_) => 6
    DoubleValue(_) => 7
    ByteValue(_) => 8
    ShortValue(_) => 9
    IntValue(_) => 10
    LongValue(_) => 11
  }
}

///|
pub fn value_type_name(kind : Int) -> String raise ParseError {
  match kind {
    2 => "object"
    4 => "boolean"
    5 => "char"
    6 => "float"
    7 => "double"
    8 => "byte"
    9 => "short"
    10 => "int"
    11 => "long"
    _ => raise Invalid(0, "unknown value type: \{kind}")
  }
}

///|
pub struct FieldSpec {
  name_id : UInt64
  kind : Int
}

///|
pub struct StaticField {
  name_id : UInt64
  value : Value
}

///|
pub struct ConstantEntry {
  index : Int
  value : Value
}

///|
pub struct ClassInfo {
  id : UInt64
  stack_serial : UInt64
  superclass_id : UInt64
  loader_id : UInt64
  signers_id : UInt64
  protection_domain_id : UInt64
  instance_size : Int
  constants : Array[ConstantEntry]
  statics : Array[StaticField]
  fields : Array[FieldSpec]
}

///|
pub enum ObjectKind {
  Instance
  ObjectArray
  PrimitiveArray
} derive(Eq)

///|
pub extend ObjectKind with Eq::{equal, not_equal}

///|
pub fn ObjectKind::label(self : ObjectKind) -> String {
  match self {
    Instance => "instance"
    ObjectArray => "object_array"
    PrimitiveArray => "primitive_array"
  }
}

///|
/// Payload byte lengths describe the file, never JVM allocation/retained size.
pub struct ObjectInfo {
  id : UInt64
  kind : ObjectKind
  class_id : UInt64
  stack_serial : UInt64
  primitive_kind : Int
  length : Int
  payload_offset : Int
  payload_bytes : Int
}

///|
pub struct RootInfo {
  tag : Int
  object_id : UInt64
  related_id : UInt64
  thread_serial : UInt64
  frame_number : UInt64
}

///|
pub fn RootInfo::label(self : RootInfo) -> String {
  match self.tag {
    0xff => "unknown"
    1 => "jni_global"
    2 => "jni_local"
    3 => "java_frame"
    4 => "native_stack"
    5 => "sticky_class"
    6 => "thread_block"
    7 => "monitor_used"
    8 => "thread_object"
    _ => "unsupported"
  }
}

///|
pub struct StackFrame {
  id : UInt64
  method_name_id : UInt64
  signature_id : UInt64
  source_name_id : UInt64
  class_serial : UInt64
  line_number : Int
}

///|
pub struct StackTrace {
  serial : UInt64
  thread_serial : UInt64
  frame_ids : Array[UInt64]
}

///|
pub struct ThreadInfo {
  serial : UInt64
  object_id : UInt64
  stack_serial : UInt64
  name_id : UInt64
  group_name_id : UInt64
  parent_group_name_id : UInt64
}

///|
pub struct FieldValue {
  declaring_class_id : UInt64
  name : String
  value : Value
}

///|
pub struct ReferenceEdge {
  source_id : UInt64
  target_id : UInt64
  label : String
}

///|
/// Histogram row for one class identity or primitive-array element type.
pub struct HistogramRow {
  name : String
  class_id : UInt64
  loader_id : UInt64
  kind : String
  count : Int
  payload_bytes : Int64
  elements : Int64
}

///|
pub struct ResolvedFrame {
  id : UInt64
  class_name : String
  method_name : String
  signature : String
  source_name : String
  line_number : Int
}

///|
fn Reader::value(self : Reader, kind : Int) -> Value raise ParseError {
  match kind {
    2 => Reference(self.id())
    4 => {
      let n = self.u1()
      if n > 1 {
        raise Invalid(self.pos - 1, "invalid boolean value")
      }
      Boolean(n == 1)
    }
    5 => Character(self.u2())
    6 =>
      FloatValue(
        Float::reinterpret_from_uint(self.number(4).to_uint()).to_double(),
      )
    7 => DoubleValue(self.number(8).reinterpret_as_double())
    8 => {
      let n = self.u1()
      ByteValue(if n >= 128 { n - 256 } else { n })
    }
    9 => {
      let n = self.u2()
      ShortValue(if n >= 32768 { n - 65536 } else { n })
    }
    10 => IntValue(self.number(4).to_int())
    11 => LongValue(self.number(8).reinterpret_as_int64())
    _ => raise Invalid(self.pos, "invalid field type: \{kind}")
  }
}
