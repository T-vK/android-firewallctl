/*
 * Request allow via root watcher (FIFO wake, no su from the system app).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

final class AllowHelper {

    private static final String TAG = "FirewallNotify";

    private static final String ALLOW_FIFO =
            "/data/local/tmp/firewall_default_deny_allow.fifo";

    private static final String QUEUE_LOCAL = "/data/local/tmp/firewall_default_deny_allow";

    private static final String QUEUE_STATE =
            "/data/adb/firewall_default_deny/allow_queue";

    /** Written by firewall-watcher after firewall-allow-app succeeds. */
    private static final String ALLOW_DONE =
            "/data/local/tmp/firewall_default_deny_done";

    private static final String ALLOWLIST =
            "/data/adb/firewall_default_deny/allowlist.txt";

    private static final int ALLOW_WAIT_MS = 8000;

    private AllowHelper() {
    }

    /** Queue or run allow; returns true only when policy was actually cleared. */
    static boolean allowPackage(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        if (writeFifo(pkg) || appendQueue(pkg)) {
            return waitForAllowComplete(pkg, ALLOW_WAIT_MS);
        }
        return runAllowAsRoot(pkg);
    }

    static boolean waitForAllowComplete(String pkg, int timeoutMs) {
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (System.currentTimeMillis() < deadline) {
            if (isPkgListedInFile(ALLOW_DONE, pkg) || isPkgInAllowlist(pkg)) {
                removePkgFromDoneFile(pkg);
                return true;
            }
            try {
                Thread.sleep(50);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return false;
            }
        }
        return false;
    }

    private static boolean isPkgListedInFile(String path, String pkg) {
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(new FileInputStream(path), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (pkg.equals(line.trim())) {
                    return true;
                }
            }
        } catch (Throwable ignored) {
            /* not readable yet */
        }
        return false;
    }

    private static boolean isPkgInAllowlist(String pkg) {
        return isPkgListedInFile(ALLOWLIST, pkg);
    }

    private static void removePkgFromDoneFile(String pkg) {
        File f = new File(ALLOW_DONE);
        if (!f.isFile()) {
            return;
        }
        List<String> keep = new ArrayList<>();
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(new FileInputStream(f), StandardCharsets.UTF_8))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (!pkg.equals(line.trim())) {
                    keep.add(line);
                }
            }
        } catch (Throwable ignored) {
            return;
        }
        try (FileOutputStream fos = new FileOutputStream(f, false)) {
            for (int i = 0; i < keep.size(); i++) {
                if (i > 0) {
                    fos.write('\n');
                }
                fos.write(keep.get(i).getBytes(StandardCharsets.UTF_8));
            }
            if (!keep.isEmpty()) {
                fos.write('\n');
            }
        } catch (Throwable ignored) {
            /* best-effort */
        }
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

    private static boolean runAllowAsRoot(String pkg) {
        String[][] attempts = {
                {"/system/bin/su", "-c", "/system/bin/firewall-allow-app " + pkg},
                {"/system/bin/su", "0", "/system/bin/firewall-allow-app", pkg},
                {"/system/bin/firewall-allow-app", pkg},
        };
        for (String[] cmd : attempts) {
            if (run(cmd) == 0) {
                return true;
            }
            Log.w(TAG, "allow su failed");
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
