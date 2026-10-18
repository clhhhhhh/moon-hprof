///|
fn be(value : UInt64, width : Int) -> Bytes {
  Bytes::makei(width, i => ((value >> ((width - i - 1) * 8)) & 255UL).to_byte())
}

///|
fn record(tag : Int, body : Bytes) -> Bytes {
  be(tag.to_uint64(), 1) + be(0UL, 4) + be(body.length().to_uint64(), 4) + body
}

///|
fn string_record(id : UInt64, text : String, width : Int) -> Bytes {
  record(1, be(id, width) + encode_hprof_text(text))
}

///|
fn load_record(serial : Int, id : UInt64, name : UInt64, width : Int) -> Bytes {
  record(
    2,
    be(serial.to_uint64(), 4) + be(id, width) + be(0UL, 4) + be(name, width),
  )
}

///|
fn class_record(
  id : UInt64,
  parent : UInt64,
  width : Int,
  fields : Array[(UInt64, Int)],
  statics : Array[(UInt64, Int, Bytes)],
) -> Bytes {
  let mut body = be(id, width) +
    be(0UL, 4) +
    be(parent, width) +
    be(55UL, width) +
    Bytes::make(width * 4, 0) +
    be(64UL, 4)
  body += be(0UL, 2) // empty constant pool
  body += be(statics.length().to_uint64(), 2)
  for entry in statics {
    body += be(entry.0, width) + be(entry.1.to_uint64(), 1) + entry.2
  }
  body += be(fields.length().to_uint64(), 2)
  for field in fields {
    body += be(field.0, width) + be(field.1.to_uint64(), 1)
  }
  be(0x20UL, 1) + body
}

///|
fn instance_record(
  id : UInt64,
  cls : UInt64,
  payload : Bytes,
  width : Int,
) -> Bytes {
  be(0x21UL, 1) +
  be(id, width) +
  be(0UL, 4) +
  be(cls, width) +
  be(payload.length().to_uint64(), 4) +
  payload
}

///|
fn object_array_record(
  id : UInt64,
  cls : UInt64,
  ids : Array[UInt64],
  width : Int,
) -> Bytes {
  let mut body = be(0x22UL, 1) +
    be(id, width) +
    be(0UL, 4) +
    be(ids.length().to_uint64(), 4) +
    be(cls, width)
  for id in ids {
    body += be(id, width)
  }
  body
}

///|
fn primitive_array_record(
  id : UInt64,
  kind : Int,
  count : Int,
  payload : Bytes,
  width : Int,
) -> Bytes {
  be(0x23UL, 1) +
  be(id, width) +
  be(0UL, 4) +
  be(count.to_uint64(), 4) +
  be(kind.to_uint64(), 1) +
  payload
}

///|
fn wrap_heap(heap : Bytes, width : Int, records? : Bytes = b"") -> Bytes {
  b"JAVA PROFILE 1.0.2\x00" +
  be(width.to_uint64(), 4) +
  be(123456789UL, 8) +
  records +
  record(0x1c, heap) +
  record(0x2c, b"")
}

///|
fn sample_dump(width : Int) -> Bytes {
  let names = [
    "pkg/Base", "pkg/Child", "base", "count", "ref", "truth", "character", "small",
    "medium", "wide", "floating", "double", "staticRef", "[Lpkg/Child;", "run", "()V",
    "Sample.java", "worker",
  ]
  let mut records = b""
  for i in 0..<names.length() {
    records += string_record((i + 1).to_uint64(), names[i], width)
  }
  records += load_record(1, 100UL, 1UL, width)
  records += load_record(2, 101UL, 2UL, width)
  records += load_record(3, 102UL, 14UL, width)
  records += record(
    4,
    be(900UL, width) +
    be(15UL, width) +
    be(16UL, width) +
    be(17UL, width) +
    be(2UL, 4) +
    be(123UL, 4),
  )
  records += record(5, be(7UL, 4) + be(9UL, 4) + be(1UL, 4) + be(900UL, width))
  records += record(
    0x0a,
    be(9UL, 4) +
    be(200UL, width) +
    be(7UL, 4) +
    be(18UL, width) +
    be(0UL, width) +
    be(0UL, width),
  )
  let mut heap = class_record(100UL, 0UL, width, [(3UL, 10)], [])
  heap += class_record(
    101UL,
    100UL,
    width,
    [
      (4UL, 10),
      (5UL, 2),
      (6UL, 4),
      (7UL, 5),
      (8UL, 8),
      (9UL, 9),
      (10UL, 11),
      (11UL, 6),
      (12UL, 7),
    ],
    [(13UL, 2, be(201UL, width))],
  )
  heap += class_record(102UL, 0UL, width, [], [])
  let payload = be(42UL, 4) +
    be(201UL, width) +
    be(1UL, 1) +
    be(0x4e2dUL, 2) +
    be(249UL, 1) +
    be(65236UL, 2) +
    be((-9000000000L).reinterpret_as_uint64(), 8) +
    be(0x3fc00000UL, 4) +
    be(0xc002000000000000UL, 8) +
    be(0xffffff9dUL, 4)
  heap += instance_record(200UL, 101UL, payload, width)
  heap += instance_record(201UL, 100UL, be(8UL, 4), width)
  heap += object_array_record(300UL, 102UL, [200UL, 0UL, 201UL], width)
  heap += primitive_array_record(301UL, 8, 3, b"\xff\x00\x07", width)
  heap += primitive_array_record(302UL, 5, 2, b"\x00A\x4e\x2d", width)
  heap += be(5UL, 1) + be(101UL, width)
  heap += be(3UL, 1) + be(200UL, width) + be(9UL, 4) + be(0UL, 4)
  wrap_heap(heap, width, records~)
}
