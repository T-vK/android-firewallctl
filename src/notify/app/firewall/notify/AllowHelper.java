/*
 * Allow: Magisk su when granted, else queue for root watcher (priv-app / no su).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

final class AllowHelper {

    private static final String TAG = "FirewallNotify";

    private static final String QUEUE_LOCAL = "/data/local/tmp/firewall_default_deny_allow";

    private static final String QUEUE_STATE =
            "/data/adb/firewall_default_deny/allow_queue";

    private AllowHelper() {
    }

    static boolean allowPackage(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        if (runRootAllow(pkg) == 0) {
            Log.i(TAG, "allow ok (root): " + pkg);
            return true;
        }
        if (appendQueue(pkg)) {
            Log.i(TAG, "allow queued for watcher: " + pkg);
            return true;
        }
        Log.w(TAG, "allow failed: no su and queue write failed for " + pkg);
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

    private static boolean appendQueue(String pkg) {
        byte[] line = (pkg + "\n").getBytes(StandardCharsets.UTF_8);
        for (String path : new String[] {QUEUE_LOCAL, QUEUE_STATE}) {
            try {
                File file = new File(path);
                File parent = file.getParentFile();
                if (parent != null && !parent.exists()) {
                    parent.mkdirs();
                }
                FileOutputStream fos = new FileOutputStream(file, true);
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
