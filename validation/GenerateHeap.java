import java.lang.management.ManagementFactory;
import com.sun.management.HotSpotDiagnosticMXBean;

/** Produces a small real heap with known reachable application objects. */
public final class GenerateHeap {
    static final class Marker {
        final int sequence;
        final byte[] payload;
        Marker(int sequence) {
            this.sequence = sequence;
            this.payload = new byte[sequence + 1];
        }
    }
    static final Marker[] KEEP = new Marker[37];
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("output.hprof");
        for (int i = 0; i < KEEP.length; i++) KEEP[i] = new Marker(i);
        ManagementFactory.getPlatformMXBean(HotSpotDiagnosticMXBean.class)
            .dumpHeap(args[0], true);
        System.out.println("reachable Marker instances=" + KEEP.length);
    }
}
