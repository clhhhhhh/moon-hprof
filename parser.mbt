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
} derive(Debug)

///|
pub extend Summary with @moonbitlang/core/debug.Debug::{to_repr}

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
fn read_class(r : Reader) -> Unit raise ParseError {
  // class ID, stack serial, superclass/loader/signers/domain/two reserved IDs.
  r.skip(r.id_size * 7 + 8)
  let constants = r.u2()
  for _ in 0..<constants {
    r.skip(2)
    let kind = r.u1()
    r.skip(type_width(kind, r.id_size))
  }
  let statics = r.u2()
  for _ in 0..<statics {
    r.skip(r.id_size)
    let kind = r.u1()
    r.skip(type_width(kind, r.id_size))
  }
  let fields = r.u2()
  for _ in 0..<fields {
    r.skip(r.id_size)
    ignore(type_width(r.u1(), r.id_size))
  }
}

///|
fn read_heap(r : Reader, summary : Summary) -> Unit raise ParseError {
  while r.pos < r.end {
    let offset = r.pos
    let tag = r.u1()
    match tag {
      0xff | 0x05 | 0x07 => r.skip(r.id_size)
      0x01 => r.skip(r.id_size * 2)
      0x02 | 0x03 | 0x08 => r.skip(r.id_size + 8)
      0x04 | 0x06 => r.skip(r.id_size + 4)
      0x20 => {
        read_class(r)
        summary.classes += 1
      }
      0x21 => {
        r.skip(r.id_size + 4)
        let class_id = r.id()
        let length = r.length()
        r.skip(length)
        summary.instances += 1
        summary.counts[class_id] = summary.counts.get(class_id).unwrap_or(0) + 1
      }
      0x22 => {
        r.skip(r.id_size + 4)
        let count = r.length()
        r.skip(r.id_size)
        if count > (r.end - r.pos) / r.id_size {
          raise Invalid(offset, "truncated object array")
        }
        r.skip(count * r.id_size)
        summary.object_arrays += 1
      }
      0x23 => {
        r.skip(r.id_size + 4)
        let count = r.length()
        let kind = r.u1()
        if kind == 2 {
          raise Invalid(offset, "object type in primitive array")
        }
        let width = type_width(kind, r.id_size)
        if count > (r.end - r.pos) / width {
          raise Invalid(offset, "truncated primitive array")
        }
        r.skip(count * width)
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
  r.skip(8)
  let summary = Summary::{
    id_size,
    classes: 0,
    instances: 0,
    object_arrays: 0,
    primitive_arrays: 0,
    strings: {},
    class_names: {},
    counts: {},
  }
  let mut heap_seen = false
  let mut end_seen = false
  while r.pos < r.end {
    let tag = r.u1()
    r.skip(4)
    let size = r.length()
    let start = r.pos
    r.skip(size)
    let record = Reader::{ data, pos: start, end: r.pos, id_size, }
    match tag {
      1 => {
        let id = record.id()
        summary.strings[id] = @utf8.decode_lossy(data[record.pos:record.end])
      }
      2 => {
        record.skip(4)
        let class_id = record.id()
        record.skip(4)
        summary.class_names[class_id] = record.id()
        if record.pos != record.end {
          raise Invalid(start, "invalid LOAD_CLASS size")
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
