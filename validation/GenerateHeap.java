import java.lang.management.ManagementFactory;
import com.sun.management.HotSpotDiagnosticMXBean;

/** Produces a small real heap with known reachable application objects. */
public final class GenerateHeap {
    static class Base {
        final long inherited = -9000000000L;
    }
    static final class Marker extends Base {
        final int sequence;
        final byte[] payload;
        Marker(int sequence) {
            this.sequence = sequence;
            this.payload = new byte[sequence + 1];
        }
    }
    static final Marker[] KEEP = new Marker[37];
    static final String TEXT = "A\u0000\u4e2d\ud83d\ude00";
    static final Object[] ARRAYS = {
        new boolean[] {true, false, true}, new char[] {'A', '\u4e2d', '\ud83d', '\ude00'},
        new byte[] {-1, 0, 127}, new short[] {-300, 0, 32767},
        new int[] {-2147483648, 42, 2147483647},
        new long[] {Long.MIN_VALUE, -9000000000L, Long.MAX_VALUE},
        new float[] {1.5f, Float.NaN, Float.POSITIVE_INFINITY},
        new double[] {-2.25, Double.NaN, Double.NEGATIVE_INFINITY}
    };
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("output.hprof");
        for (int i = 0; i < KEEP.length; i++) KEEP[i] = new Marker(i);
        ManagementFactory.getPlatformMXBean(HotSpotDiagnosticMXBean.class)
            .dumpHeap(args[0], true);
        System.out.println("reachable Marker instances=" + KEEP.length);
    }
}
