import java.io.File;
import java.util.HashMap;
import java.util.Map;
import edu.tufts.eaftan.hprofparser.parser.HprofParser;
import edu.tufts.eaftan.hprofparser.handler.NullRecordHandler;
import edu.tufts.eaftan.hprofparser.parser.datastructures.*;

/** Adapter only: all binary decoding is performed by eaftan/hprof-parser. */
public final class ReferenceCounts extends NullRecordHandler {
    int classes, instances, objectArrays, primitiveArrays;
    final Map<Long, String> strings = new HashMap<>();
    final Map<Long, Long> names = new HashMap<>();
    final Map<Long, Integer> counts = new HashMap<>();
    public void stringInUTF8(long id, String text) { strings.put(id, text); }
    public void loadClass(int serial, long id, int stack, long name) { names.put(id, name); }
    public void classDump(long id, int stack, long parent, long loader, long signers,
            long domain, long r1, long r2, int size, Constant[] constants,
            Static[] statics, InstanceField[] fields) { classes++; }
    public void instanceDump(long id, int stack, long cls, Value<?>[] values) {
        instances++;
        counts.merge(cls, 1, Integer::sum);
    }
    public void objArrayDump(long id, int stack, long cls, long[] elems) { objectArrays++; }
    public void primArrayDump(long id, int stack, byte type, Value<?>[] elems) { primitiveArrays++; }
    public static void main(String[] args) throws Exception {
        ReferenceCounts h = new ReferenceCounts();
        new HprofParser(h).parse(new File(args[0]));
        int markers = 0;
        for (Map.Entry<Long, Long> e : h.names.entrySet()) {
            if ("GenerateHeap$Marker".equals(h.strings.get(e.getValue())))
                markers += h.counts.getOrDefault(e.getKey(), 0);
        }
        System.out.println("classes=" + h.classes);
        System.out.println("instances=" + h.instances);
        System.out.println("object_arrays=" + h.objectArrays);
        System.out.println("primitive_arrays=" + h.primitiveArrays);
        System.out.println("markers=" + markers);
    }
}
