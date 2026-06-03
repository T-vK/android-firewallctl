/*
 * Request allow via root watcher (FIFO wake, no su from the system app).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

final class AllowHelper {

    private static final String TAG = "FirewallNotify";

    /** Named pipe: watcher blocks on read, instant allow (no polling). */
    private static final String ALLOW_FIFO =
            "/data/local/tmp/firewall_default_deny_allow.fifo";

    /** Append fallback; watcher uses inotify on close_write. */
    private static final String QUEUE_LOCAL = "/data/local/tmp/firewall_default_deny_allow";

    private static final String QUEUE_STATE =
            "/data/adb/firewall_default_deny/allow_queue";

    private AllowHelper() {
    }

    static boolean allowPackage(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        if (writeFifo(pkg)) {
            return true;
        }
        if (appendQueue(pkg)) {
            return true;
        }
        return runAllowAsRoot(pkg);
    }

    private static boolean writeFifo(String pkg) {
        try {
            FileOutputStream fos = new FileOutputStream(ALLOW_FIFO);
            fos.write((pkg + "\n").getBytes(StandardCharsets.UTF_8));
            fos.close();
            Log.i(TAG, "allow fifo: " + pkg);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "allow fifo: " + t.getMessage());
            return false;
        }
    }

    private static boolean appendQueue(String pkg) {
        byte[] line = (pkg + "\n").getBytes(StandardCharsets.UTF_8);
        for (String path : new String[] {QUEUE_LOCAL, QUEUE_STATE}) {
            try {
                File f = new File(path);
                File parent = f.getParentFile();
                if (parent != null && !parent.exists()) {
                    parent.mkdirs();
                }
                FileOutputStream fos = new FileOutputStream(f, true);
                fos.write(line);
                fos.close();
                Log.i(TAG, "allow queue: " + pkg + " via " + path);
                return true;
            } catch (Throwable t) {
                Log.w(TAG, "allow queue " + path + ": " + t.getMessage());
            }
        }
        return false;
    }

    private static boolean runAllowAsRoot(String pkg) {
        String[][] attempts = {
                {"/system/bin/su", "-c", "/system/bin/firewall-allow-app " + pkg},
                {"/system/bin/su", "0", "/system/bin/firewall-allow-app", pkg},
                {"/system/bin/firewall-allow-app", pkg},
        };
        for (String[] cmd : attempts) {
            int rc = run(cmd);
            if (rc == 0) {
                return true;
            }
            Log.w(TAG, "allow su failed rc=" + rc);
        }
        return false;
    }

    private static int run(String[] cmd) {
        try {
            Process p = new ProcessBuilder(cmd)
                    .redirectErrorStream(true)
                    .start();
            return p.waitFor();
        } catch (Throwable t) {
            Log.w(TAG, "allow exec: " + t.getMessage());
            return -1;
        }
    }
}
