/*
 * Request allow via root watcher (queue wake, no su from the system app).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

final class AllowHelper {

    private static final String TAG = "FirewallNotify";

    static final String COMPLETE_MARKER_NAME = "firewall_allow_complete";

    private static final String ALLOW_FIFO =
            "/data/local/tmp/firewall_default_deny_allow.fifo";

    private static final String QUEUE_LOCAL = "/data/local/tmp/firewall_default_deny_allow";

    private static final String QUEUE_STATE =
            "/data/adb/firewall_default_deny/allow_queue";

    private static final int ALLOW_WAIT_MS = 15000;

    private AllowHelper() {
    }

    static File completeMarkerFile(Context ctx) {
        if (ctx == null) {
            return null;
        }
        return new File(ctx.getCacheDir(), COMPLETE_MARKER_NAME);
    }

    static void clearCompleteMarker(Context ctx) {
        File marker = completeMarkerFile(ctx);
        if (marker != null && marker.exists()) {
            marker.delete();
        }
    }

    /** Queue allow to root watcher; returns true when watcher confirms success. */
    static boolean allowPackage(Context ctx, String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        clearCompleteMarker(ctx);
        BroadcastReceiver receiver = registerAllowReceiver(ctx, pkg);
        try {
            AllowCompleteReceiver.beginWait(pkg);
            boolean queued = appendQueue(pkg) || writeFifo(pkg);
            if (!queued) {
                AllowCompleteReceiver.clear();
                return runAllowAsRoot(pkg);
            }
            return AllowCompleteReceiver.awaitComplete(ctx, pkg, ALLOW_WAIT_MS);
        } finally {
            unregisterAllowReceiver(ctx, receiver);
        }
    }

    private static BroadcastReceiver registerAllowReceiver(Context ctx, final String pkg) {
        if (ctx == null) {
            return null;
        }
        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent intent) {
                if (intent == null
                        || !AllowCompleteReceiver.ACTION_ALLOW_COMPLETE.equals(
                                intent.getAction())) {
                    return;
                }
                String p = intent.getStringExtra(NotifyHelper.EXTRA_PACKAGE);
                if (pkg.equals(p)) {
                    AllowCompleteReceiver.signalComplete(pkg);
                }
            }
        };
        IntentFilter filter =
                new IntentFilter(AllowCompleteReceiver.ACTION_ALLOW_COMPLETE);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                ctx.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                ctx.registerReceiver(receiver, filter);
            }
            return receiver;
        } catch (Throwable t) {
            Log.w(TAG, "allow receiver register: " + t.getMessage());
            return null;
        }
    }

    private static void unregisterAllowReceiver(Context ctx, BroadcastReceiver receiver) {
        if (ctx == null || receiver == null) {
            return;
        }
        try {
            ctx.unregisterReceiver(receiver);
        } catch (Throwable ignored) {
            /* already unregistered */
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
