/*
 * Allow network via Magisk su + root watcher (same path as manual "su -c firewall-allow-app").
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

final class AllowHelper {

    private static final String TAG = "FirewallNotify";

    private AllowHelper() {
    }

    /**
     * Runs {@code firewall-watcher --allow <pkg>} as root. Requires Magisk superuser
     * granted to this app (user-installed APK, not a system app).
     */
    static boolean allowPackage(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        int rc = runRootAllow(pkg);
        if (rc == 0) {
            Log.i(TAG, "allow ok: " + pkg);
            return true;
        }
        Log.w(TAG, "allow failed rc=" + rc + " pkg=" + pkg + " (grant Magisk su to Firewall Notify)");
        return false;
    }

    private static int runRootAllow(String pkg) {
        String su = findSu();
        String[][] attempts = {
                {su, "0", "/system/bin/firewall-watcher", "--allow", pkg},
                {su, "-c", "/system/bin/firewall-watcher --allow " + pkg},
                {su, "0", "/system/bin/firewall-allow-app", pkg},
                {su, "-c", "/system/bin/firewall-allow-app " + pkg},
        };
        int last = -1;
        for (String[] cmd : attempts) {
            last = run(cmd);
            if (last == 0) {
                return 0;
            }
        }
        return last;
    }

    private static String findSu() {
        for (String path : new String[] {
                "/system/bin/su",
                "/sbin/su",
                "/product/bin/su",
                "/apex/com.android.runtime/bin/su"
        }) {
            if (new File(path).canExecute()) {
                return path;
            }
        }
        return "su";
    }

    private static int run(String[] cmd) {
        try {
            Process p = new ProcessBuilder(cmd)
                    .redirectErrorStream(true)
                    .start();
            String line;
            BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
            while ((line = br.readLine()) != null) {
                Log.i(TAG, "allow: " + line);
            }
            br.close();
            return p.waitFor();
        } catch (Throwable t) {
            Log.w(TAG, "allow exec: " + t.getMessage());
            return -1;
        }
    }
}
