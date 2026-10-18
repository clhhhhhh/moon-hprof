///|
/// Aggregates by class-loader object ID; zero is the bootstrap/primitive group.
pub struct LoaderStatistics {
  loader_id : UInt64
  class_count : Int
  instance_count : Int
  array_count : Int
  payload_bytes : Int64
}

///|
pub fn Summary::loader_statistics(self : Summary) -> Array[LoaderStatistics] {
  let rows : Map[UInt64, LoaderStatistics] = Map([])
  for _, cls in self.definitions {
    let old = rows.get(cls.loader_id)
    rows[cls.loader_id] = {
      loader_id: cls.loader_id,
      class_count: old.map(row => row.class_count).unwrap_or(0) + 1,
      instance_count: 0,
      array_count: 0,
      payload_bytes: 0L,
    }
  }
  for _, object in self.objects {
    let loader_id = match self.definitions.get(object.class_id) {
      Some(cls) => cls.loader_id
      None => 0UL
    }
    let old = rows.get(loader_id)
    rows[loader_id] = {
      loader_id,
      class_count: old.map(row => row.class_count).unwrap_or(0),
      instance_count: old.map(row => row.instance_count).unwrap_or(0) +
      (if object.kind == Instance { 1 } else { 0 }),
      array_count: old.map(row => row.array_count).unwrap_or(0) +
      (if object.kind != Instance { 1 } else { 0 }),
      payload_bytes: old.map(row => row.payload_bytes).unwrap_or(0L) +
      object.payload_bytes.to_int64(),
    }
  }
  let result = rows.values().to_array()
  result.sort_by((a, b) => a.loader_id.compare(b.loader_id))
  result
}

///|
pub fn LoaderStatistics::to_json(self : LoaderStatistics) -> Json {
  Json::object({
    "loader_id": json_id(self.loader_id),
    "classes": json_int(self.class_count),
    "instances": json_int(self.instance_count),
    "arrays": json_int(self.array_count),
    "payload_bytes": Json::string(self.payload_bytes.to_string()),
  })
}
