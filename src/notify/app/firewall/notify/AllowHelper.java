/*
 * Run firewall-allow-app as root (Magisk su variants).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.util.Log;

final class AllowHelper {

    private static final String TAG = "FirewallNotify";

    private AllowHelper() {
    }

    static boolean allowPackage(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
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
