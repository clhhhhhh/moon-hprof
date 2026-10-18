///|
pub fn cli_help() -> String {
  "moon-hprof <summary|histogram|objects|object|class|roots|stack|refs|check> <file.hprof> [id] [options]\n" +
  "moon-hprof diff <before.hprof> <after.hprof> (class-name aggregate comparison)\n" +
  "  summary:   [--class internal/name] [--format text|json]\n" +
  "  histogram: [--prefix name] [--kind instance|object_array|primitive_array]\n" +
  "             [--sort count|payload|elements|name] [--format json|csv] [--offset N] [--limit N]\n" +
  "  object:    <decimal-or-hex-id> [--offset N] [--limit N]\n" +
  "  objects:   <class-id-or-0-for-all> [--offset N] [--limit N]\n" +
  "  class:     <decimal-or-hex-id>\n" +
  "  roots:     [--offset N] [--limit N]\n" +
  "  stack:     <trace-serial>\n" +
  "  refs:      <object-id> [--limit N]\n" +
  "  check:     validate class layouts and metadata\n" +
  "JSON IDs and 64-bit integers are decimal strings; payload sizes are file bytes."
}

///|
pub fn parse_object_id(text : String) -> UInt64 raise ParseError {
  let chars = text.to_array()
  let hex = text.has_prefix("0x") || text.has_prefix("0X")
  let start = if hex { 2 } else { 0 }
  let base = if hex { 16UL } else { 10UL }
  if chars.length() == start {
    raise Invalid(0, "empty object ID")
  }
  let mut value = 0UL
  for i in start..<chars.length() {
    let char = chars[i].to_int()
    let digit = if char >= 48 && char <= 57 {
      char - 48
    } else if hex && char >= 65 && char <= 70 {
      char - 55
    } else if hex && char >= 97 && char <= 102 {
      char - 87
    } else {
      raise Invalid(i, "invalid object ID digit")
    }
    if digit.to_uint64() >= base ||
      value > (18446744073709551615UL - digit.to_uint64()) / base {
      raise Invalid(i, "object ID out of range")
    }
    value = value * base + digit.to_uint64()
  }
  value
}

///|
fn cli_int(text : String) -> Int raise ParseError {
  let value = parse_object_id(text)
  if value > 2_147_483_647UL {
    raise Invalid(0, "integer option out of range")
  }
  value.to_int()
}

///|
priv struct CliOptions {
  command : String
  id : UInt64
  format : String
  offset : Int
  limit : Int
  name : String
  prefix : String
  kind : String
  sort : HistogramSort
}

///|
fn parse_cli(args : Array[String]) -> CliOptions raise ParseError {
  if args.is_empty() {
    raise Invalid(0, "missing command")
  }
  let command = args[0]
  if ![
      "summary", "histogram", "objects", "object", "class", "roots", "stack", "refs",
      "check",
    ].contains(command) {
    raise Invalid(0, "unknown command: \{command}")
  }
  let needs_id = ["objects", "object", "class", "stack", "refs"].contains(
    command,
  )
  let id = if needs_id {
    if args.length() < 2 {
      raise Invalid(0, "missing object ID or trace serial")
    }
    parse_object_id(args[1])
  } else {
    0UL
  }
  let mut format = if command == "summary" { "text" } else { "json" }
  let mut offset = 0
  let mut limit = 100
  let mut name = ""
  let mut prefix = ""
  let mut kind = ""
  let mut sort = HistogramSort::Count
  let seen : Map[String, Bool] = Map([])
  let mut i = if needs_id { 2 } else { 1 }
  while i < args.length() {
    let option = args[i]
    if seen.contains(option) {
      raise Invalid(i, "duplicate option: \{option}")
    }
    seen[option] = true
    if i + 1 >= args.length() {
      raise Invalid(i, "missing option value")
    }
    let value = args[i + 1]
    match option {
      "--format" if command == "summary" || command == "histogram" =>
        format = value
      "--class" if command == "summary" => name = value
      "--prefix" if command == "histogram" => prefix = value
      "--kind" if command == "histogram" => kind = value
      "--sort" if command == "histogram" =>
        sort = match value {
          "count" => Count
          "payload" => Payload
          "elements" => Elements
          "name" => Name
          _ => raise Invalid(i, "invalid histogram sort")
        }
      "--offset" if ["histogram", "objects", "object", "roots"].contains(
          command,
        ) => offset = cli_int(value)
      "--limit" if ["histogram", "objects", "object", "roots", "refs"].contains(
          command,
        ) => limit = cli_int(value)
      _ => raise Invalid(i, "option not supported for command: \{option}")
    }
    i += 2
  }
  if limit > 100_000 {
    raise Invalid(0, "limit must not exceed 100000")
  }
  if command == "summary" && format != "text" && format != "json" {
    raise Invalid(0, "summary format must be text or json")
  }
  if command == "histogram" && format != "json" && format != "csv" {
    raise Invalid(0, "histogram format must be json or csv")
  }
  { command, id, format, offset, limit, name, prefix, kind, sort, }
}

///|
/// Pure command rendering: no process globals, filesystem, or console effects.
pub fn execute(
  heap : Summary,
  arguments : Array[String],
) -> String raise ParseError {
  let options = parse_cli(arguments)
  match options.command {
    "summary" => {
      if options.format == "json" {
        let json = heap.summary_json()
        match json {
          Object(fields) =>
            if options.name != "" {
              fields["class_instances"] = json_int(
                heap.count_class(options.name),
              )
            }
          _ => ()
        }
        return json.stringify()
      }
      let text = "classes=\{heap.classes}\ninstances=\{heap.instances}\n" +
        "object_arrays=\{heap.object_arrays}\nprimitive_arrays=\{heap.primitive_arrays}"
      if options.name != "" {
        text + "\nclass_instances=\{heap.count_class(options.name)}"
      } else {
        text
      }
    }
    "histogram" => {
      let rows = heap.select_histogram(
        prefix=options.prefix,
        kind=options.kind,
        sort=options.sort,
        offset=options.offset,
        limit=options.limit,
      )
      if options.format == "json" {
        Json::array(rows.map(row => row.to_json())).stringify()
      } else {
        let out = StringBuilder()
        out.write_string(
          "name,class_id,loader_id,kind,count,payload_bytes,elements\r\n",
        )
        for row in rows {
          out.write_string(
            [
              row.name,
              row.class_id.to_string(),
              row.loader_id.to_string(),
              row.kind,
              row.count.to_string(),
              row.payload_bytes.to_string(),
              row.elements.to_string(),
            ]
            .map(csv_cell)
            .join(","),
          )
          out.write_string("\r\n")
        }
        out.to_string()
      }
    }
    "objects" =>
      Json::array(
        heap
        .object_ids(
          class_id=options.id,
          offset=options.offset,
          limit=options.limit,
        )
        .map(json_id),
      ).stringify()
    "object" =>
      heap
      .object_json(options.id, offset=options.offset, limit=options.limit)
      .stringify()
    "class" => heap.class_json(options.id).stringify()
    "roots" =>
      Json::array(
        heap
        .roots(offset=options.offset, limit=options.limit)
        .map(root => root.to_json()),
      ).stringify()
    "stack" =>
      Json::array(heap.stack_trace(options.id).map(frame => frame.to_json())).stringify()
    "refs" =>
      Json::array(
        heap
        .references(options.id, limit=options.limit)
        .map(edge => edge.to_json()),
      ).stringify()
    "check" => {
      heap.validate()
      "OK"
    }
    _ => raise Invalid(0, "unreachable command")
  }
}
