///|
pub suberror ParseError {
  Invalid(Int, String)
} derive(Debug)

///|
pub extend ParseError with @moonbitlang/core/debug.Debug::{to_repr}

///|
priv struct Reader {
  data : Bytes
  mut pos : Int
  end : Int
  id_size : Int
}

///|
fn Reader::skip(self : Reader, count : Int) -> Unit raise ParseError {
  if count < 0 || count > self.end - self.pos {
    raise Invalid(self.pos, "truncated record")
  }
  self.pos += count
}

///|
fn Reader::number(self : Reader, width : Int) -> UInt64 raise ParseError {
  let start = self.pos
  self.skip(width)
  let mut value = 0UL
  for i in start..<self.pos {
    value = (value << 8) | self.data[i].to_uint64()
  }
  value
}

///|
fn Reader::u1(self : Reader) -> Int raise ParseError {
  self.number(1).to_int()
}

///|
fn Reader::u2(self : Reader) -> Int raise ParseError {
  self.number(2).to_int()
}

///|
fn Reader::length(self : Reader) -> Int raise ParseError {
  let n = self.number(4)
  if n > 2_147_483_647UL {
    raise Invalid(self.pos - 4, "length exceeds prototype limit")
  }
  n.to_int()
}

///|
fn Reader::id(self : Reader) -> UInt64 raise ParseError {
  self.number(self.id_size)
}

///|
fn type_width(kind : Int, id_size : Int) -> Int raise ParseError {
  match kind {
    2 => id_size
    4 | 8 => 1
    5 | 9 => 2
    6 | 10 => 4
    7 | 11 => 8
    _ => raise Invalid(0, "unknown value type: \{kind}")
  }
}

///|
/// Counts physical dump records, not retained heap sizes or live-object proofs.
pub struct Summary {
  id_size : Int
  mut classes : Int
  mut instances : Int
  mut object_arrays : Int
  mut primitive_arrays : Int
  priv strings : Map[UInt64, String]
  priv class_names : Map[UInt64, UInt64]
  priv counts : Map[UInt64, Int]
  priv data : Bytes
  timestamp_ms : UInt64
  priv definitions : Map[UInt64, ClassInfo]
  priv objects : Map[UInt64, ObjectInfo]
  priv roots_data : Array[RootInfo]
  priv frames : Map[UInt64, StackFrame]
  priv traces : Map[UInt64, StackTrace]
  priv threads : Map[UInt64, ThreadInfo]
  priv class_serials : Map[UInt64, UInt64]
  priv record_counts : Map[Int, Int]
}

///|
pub fn Summary::count_class(self : Summary, name : String) -> Int {
  let mut count = 0
  for class_id, string_id in self.class_names {
    if self.strings.get(string_id) == Some(name) {
      count += self.counts.get(class_id).unwrap_or(0)
    }
  }
  count
}

///|
fn read_class(r : Reader, summary : Summary) -> Unit raise ParseError {
  let id = r.id()
  if id == 0UL ||
    summary.definitions.contains(id) ||
    summary.objects.contains(id) {
    raise Invalid(r.pos, "duplicate or null class object ID")
  }
  let stack_serial = r.number(4)
  let superclass_id = r.id()
  let loader_id = r.id()
  let signers_id = r.id()
  let protection_domain_id = r.id()
  r.skip(r.id_size * 2)
  let instance_size = r.length()
  let constant_values : Array[ConstantEntry] = []
  let constants = r.u2()
  for _ in 0..<constants {
    let index = r.u2()
    let kind = r.u1()
    constant_values.push({ index, value: r.value(kind), })
  }
  let static_values : Array[StaticField] = []
  let statics = r.u2()
  for _ in 0..<statics {
    let name_id = r.id()
    let kind = r.u1()
    static_values.push({ name_id, value: r.value(kind), })
  }
  let field_values : Array[FieldSpec] = []
  let fields = r.u2()
  for _ in 0..<fields {
    let name_id = r.id()
    let kind = r.u1()
    ignore(type_width(kind, r.id_size))
    field_values.push({ name_id, kind, })
  }
  summary.definitions[id] = {
    id,
    stack_serial,
    superclass_id,
    loader_id,
    signers_id,
    protection_domain_id,
    instance_size,
    constants: constant_values,
    statics: static_values,
    fields: field_values,
  }
}

///|
fn add_object(summary : Summary, object : ObjectInfo) -> Unit raise ParseError {
  if object.id == 0UL ||
    summary.objects.contains(object.id) ||
    summary.definitions.contains(object.id) {
    raise Invalid(object.payload_offset, "duplicate or null object ID")
  }
  summary.objects[object.id] = object
}

///|
fn read_root(r : Reader, tag : Int, summary : Summary) -> Unit raise ParseError {
  let object_id = r.id()
  let related_id = if tag == 1 { r.id() } else { 0UL }
  let thread_serial = match tag {
    2 | 3 | 4 | 6 | 8 => r.number(4)
    _ => 0UL
  }
  let frame_number = match tag {
    2 | 3 | 8 => r.number(4)
    _ => 0UL
  }
  summary.roots_data.push({
    tag,
    object_id,
    related_id,
    thread_serial,
    frame_number,
  })
}

///|
fn read_heap(r : Reader, summary : Summary) -> Unit raise ParseError {
  while r.pos < r.end {
    let offset = r.pos
    let tag = r.u1()
    match tag {
      0xff | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 => read_root(r, tag, summary)
      0x20 => {
        read_class(r, summary)
        summary.classes += 1
      }
      0x21 => {
        let id = r.id()
        let stack_serial = r.number(4)
        let class_id = r.id()
        let length = r.length()
        let payload_offset = r.pos
        r.skip(length)
        add_object(summary, {
          id,
          kind: Instance,
          class_id,
          stack_serial,
          primitive_kind: 0,
          length: 0,
          payload_offset,
          payload_bytes: length,
        })
        summary.instances += 1
        summary.counts[class_id] = summary.counts.get(class_id).unwrap_or(0) + 1
      }
      0x22 => {
        let id = r.id()
        let stack_serial = r.number(4)
        let count = r.length()
        let class_id = r.id()
        if count > (r.end - r.pos) / r.id_size {
          raise Invalid(offset, "truncated object array")
        }
        let payload_offset = r.pos
        r.skip(count * r.id_size)
        add_object(summary, {
          id,
          kind: ObjectArray,
          class_id,
          stack_serial,
          primitive_kind: 2,
          length: count,
          payload_offset,
          payload_bytes: count * r.id_size,
        })
        summary.object_arrays += 1
      }
      0x23 => {
        let id = r.id()
        let stack_serial = r.number(4)
        let count = r.length()
        let kind = r.u1()
        if kind == 2 {
          raise Invalid(offset, "object type in primitive array")
        }
        let width = type_width(kind, r.id_size)
        if count > (r.end - r.pos) / width {
          raise Invalid(offset, "truncated primitive array")
        }
        let payload_offset = r.pos
        r.skip(count * width)
        add_object(summary, {
          id,
          kind: PrimitiveArray,
          class_id: 0UL,
          stack_serial,
          primitive_kind: kind,
          length: count,
          payload_offset,
          payload_bytes: count * width,
        })
        summary.primitive_arrays += 1
      }
      _ => raise Invalid(offset, "unsupported heap subrecord: \{tag}")
    }
  }
}

///|
/// Prototype for HotSpot JAVA PROFILE 1.0.2, with strict record boundaries.
/// ponytail: retains the input and name tables; streaming/mmap is future work.
pub fn parse(data : Bytes) -> Summary raise ParseError {
  let r = Reader::{ data, pos: 0, end: data.length(), id_size: 4, }
  r.skip(19)
  if data[0:19].to_owned() != b"JAVA PROFILE 1.0.2\x00" {
    raise Invalid(0, "expected JAVA PROFILE 1.0.2")
  }
  let id_size = r.length()
  if id_size != 4 && id_size != 8 {
    raise Invalid(19, "identifier width must be 4 or 8")
  }
  let timestamp_ms = r.number(8)
  let summary = Summary::{
    id_size,
    classes: 0,
    instances: 0,
    object_arrays: 0,
    primitive_arrays: 0,
    strings: {},
    class_names: {},
    counts: {},
    data,
    timestamp_ms,
    definitions: {},
    objects: {},
    roots_data: [],
    frames: {},
    traces: {},
    threads: {},
    class_serials: {},
    record_counts: {},
  }
  let mut heap_seen = false
  let mut end_seen = false
  while r.pos < r.end {
    let tag = r.u1()
    summary.record_counts[tag] = summary.record_counts.get(tag).unwrap_or(0) + 1
    r.skip(4)
    let size = r.length()
    let start = r.pos
    r.skip(size)
    let record = Reader::{ data, pos: start, end: r.pos, id_size, }
    match tag {
      1 => {
        let id = record.id()
        if summary.strings.contains(id) {
          raise Invalid(start, "duplicate string ID")
        }
        summary.strings[id] = decode_hprof_text(
          data[record.pos:record.end].to_owned(),
        )
      }
      2 => {
        let serial = record.number(4)
        let class_id = record.id()
        record.skip(4)
        summary.class_names[class_id] = record.id()
        summary.class_serials[serial] = class_id
        if record.pos != record.end {
          raise Invalid(start, "invalid LOAD_CLASS size")
        }
      }
      4 => {
        let id = record.id()
        let method_name_id = record.id()
        let signature_id = record.id()
        let source_name_id = record.id()
        let class_serial = record.number(4)
        let line_number = record.number(4).to_int()
        if record.pos != record.end || summary.frames.contains(id) {
          raise Invalid(start, "invalid or duplicate stack frame")
        }
        summary.frames[id] = {
          id,
          method_name_id,
          signature_id,
          source_name_id,
          class_serial,
          line_number,
        }
      }
      5 => {
        let serial = record.number(4)
        let thread_serial = record.number(4)
        let count = record.length()
        if count > (record.end - record.pos) / id_size {
          raise Invalid(start, "truncated stack trace")
        }
        let frame_ids = []
        for _ in 0..<count {
          frame_ids.push(record.id())
        }
        if record.pos != record.end || summary.traces.contains(serial) {
          raise Invalid(start, "invalid or duplicate stack trace")
        }
        summary.traces[serial] = { serial, thread_serial, frame_ids, }
      }
      0x0a => {
        let serial = record.number(4)
        let object_id = record.id()
        let stack_serial = record.number(4)
        let name_id = record.id()
        let group_name_id = record.id()
        let parent_group_name_id = record.id()
        if record.pos != record.end || summary.threads.contains(serial) {
          raise Invalid(start, "invalid or duplicate thread")
        }
        summary.threads[serial] = {
          serial,
          object_id,
          stack_serial,
          name_id,
          group_name_id,
          parent_group_name_id,
        }
      }
      0x0c | 0x1c => {
        if end_seen {
          raise Invalid(start, "heap segment after end")
        }
        read_heap(record, summary)
        heap_seen = true
        if tag == 0x0c {
          end_seen = true
        }
      }
      0x2c => {
        if size != 0 || !heap_seen || end_seen {
          raise Invalid(start, "invalid HEAP_DUMP_END")
        }
        end_seen = true
      }
      // Other top-level records are length-delimited and can be skipped safely.
      _ => ()
    }
  }
  if !heap_seen || !end_seen {
    raise Invalid(r.pos, "incomplete heap dump")
  }
  summary
}
