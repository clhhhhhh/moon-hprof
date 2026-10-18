///|
fn empty_dump(id_size : Int) -> Bytes {
  b"JAVA PROFILE 1.0.2\x00" +
  Bytes::from_array([0, 0, 0, id_size.to_byte()]) +
  b"\x00\x00\x00\x00\x00\x00\x00\x00" +
  b"\x1c\x00\x00\x00\x00\x00\x00\x00\x00" +
  b"\x2c\x00\x00\x00\x00\x00\x00\x00\x00"
}

///|
test "4 and 8 byte identifier headers accept an empty completed heap" {
  for width in [4, 8] {
    let summary = parse(empty_dump(width))
    assert_eq(summary.id_size, width)
    assert_eq(summary.classes, 0)
    assert_eq(summary.count_class("missing"), 0)
  }
}

///|
test "every proper prefix of the minimal dump is rejected" {
  let sample = empty_dump(8)
  for length in 0..<sample.length() {
    try parse(sample[0:length].to_owned()) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted prefix of length \{length}")
    }
  }
}

///|
test "unsupported identifier width fails explicitly" {
  try parse(empty_dump(3)) catch {
    Invalid(19, _) => ()
    other => raise other
  } noraise {
    _ => fail("accepted invalid identifier width")
  }
}

///|
test "array element count cannot escape its record boundary" {
  // Four-byte IDs, one object array claiming 2^31-1 missing elements.
  let r = Reader::{
    data: b"\x22\x00\x00\x00\x01\x00\x00\x00\x00\x7f\xff\xff\xff\x00\x00\x00\x02",
    pos: 0,
    end: 17,
    id_size: 4,
  }
  let summary = parse(empty_dump(4))
  try read_heap(r, summary) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("accepted truncated array")
  }
}

///|
test "unknown heap subrecords are rejected instead of guessing a length" {
  let r = Reader::{ data: b"\xfe", pos: 0, end: 1, id_size: 8, }
  let summary = parse(empty_dump(8))
  try read_heap(r, summary) catch {
    Invalid(0, _) => ()
    other => raise other
  } noraise {
    _ => fail("silently skipped unsupported subrecord")
  }
}
