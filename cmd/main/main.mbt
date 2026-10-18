///|
/// Summarizes a dump, optionally counting instances of one JVM class name.
fn main {
  @async.run_async_main(() => {
    let args = @env.args()
    if args.length() != 2 && args.length() != 3 {
      fail("usage: moon run cmd/main -- <heap.hprof> [internal-class-name]")
    }
    let summary = @lib.parse(@fs.read_file(args[1]).binary())
    println("classes=\{summary.classes}")
    println("instances=\{summary.instances}")
    println("object_arrays=\{summary.object_arrays}")
    println("primitive_arrays=\{summary.primitive_arrays}")
    if args.length() == 3 {
      println("class_instances=\{summary.count_class(args[2])}")
    }
  })
}
