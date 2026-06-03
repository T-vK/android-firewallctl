/*
 * Request allow via root watcher queue (no su from the system app).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

final class AllowHelper {

    private static final String TAG = "FirewallNotify";

    /** Writable by system apps; read by firewall-watcher (root). */
    private static final String QUEUE_LOCAL = "/data/local/tmp/firewall_default_deny_allow";

    /** Fallback queue under module state (created chmod 0666 at install). */
    private static final String QUEUE_STATE =
            "/data/adb/firewall_default_deny/allow_queue";

    private AllowHelper() {
    }

    static boolean allowPackage(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        if (enqueueAllow(pkg)) {
            return true;
        }
        return runAllowAsRoot(pkg);
    }

    private static boolean enqueueAllow(String pkg) {
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
                Log.i(TAG, "allow queued for " + pkg + " via " + path);
                return true;
            } catch (Throwable t) {
                Log.w(TAG, "allow queue " + path + ": " + t.getMessage());
            }
        }
        return false;
    }

    /** Last resort if queues are not writable (e.g. user granted su to this app). */
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
            Log.w(TAG, "allow failed rc=" + rc + " cmd=" + cmd[0]);
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
