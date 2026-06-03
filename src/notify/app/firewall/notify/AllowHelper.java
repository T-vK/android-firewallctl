/*
 * Allow network: prefer in-process NetworkPolicyManager (priv-app), else root watcher queue.
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

    private static final String QUEUE_LOCAL = "/data/local/tmp/firewall_default_deny_allow";

    private static final String QUEUE_STATE =
            "/data/adb/firewall_default_deny/allow_queue";

    private static final int ALLOW_WAIT_MS = 20000;

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

    /**
     * Allow network for pkg. Uses privileged NPM when available; otherwise queues work
     * for the root watcher and waits for a marker file at our cache path.
     */
    static boolean allowPackage(Context ctx, String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        clearCompleteMarker(ctx);

        if (PolicyHelper.allowNetwork(pkg)) {
            LocalAllowlist.add(ctx, pkg);
            queueRootSync(pkg);
            return true;
        }

        Log.i(TAG, "policy allow unavailable; queueing for root watcher: " + pkg);
        return allowViaWatcher(ctx, pkg);
    }

    private static void queueRootSync(String pkg) {
        byte[] line = (pkg + "\n").getBytes(StandardCharsets.UTF_8);
        for (String path : new String[] {QUEUE_LOCAL, QUEUE_STATE}) {
            try {
                File file = new File(path);
                FileOutputStream fos = new FileOutputStream(file, true);
                fos.write(line);
                fos.close();
                return;
            } catch (Throwable ignored) {
                /* watcher will still see local allowlist */
            }
        }
    }

    private static boolean allowViaWatcher(Context ctx, String pkg) {
        File marker = completeMarkerFile(ctx);
        if (marker == null) {
            return false;
        }
        BroadcastReceiver receiver = registerAllowReceiver(ctx, pkg);
        try {
            AllowCompleteReceiver.beginWait(pkg);
            if (!appendQueueWithMarker(pkg, marker)) {
                AllowCompleteReceiver.clear();
                Log.w(TAG, "allow queue write failed for " + pkg);
                return false;
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

    /** pkg TAB absolute-path-to-marker-file */
    private static boolean appendQueueWithMarker(String pkg, File marker) {
        String line = pkg + "\t" + marker.getAbsolutePath() + "\n";
        byte[] bytes = line.getBytes(StandardCharsets.UTF_8);
        for (String path : new String[] {QUEUE_LOCAL, QUEUE_STATE}) {
            try {
                File file = new File(path);
                File parent = file.getParentFile();
                if (parent != null && !parent.exists()) {
                    parent.mkdirs();
                }
                FileOutputStream fos = new FileOutputStream(file, true);
                fos.write(bytes);
                fos.close();
                Log.i(TAG, "allow queue: " + pkg + " marker=" + marker.getAbsolutePath());
                return true;
            } catch (Throwable t) {
                Log.w(TAG, "allow queue " + path + ": " + t.getMessage());
            }
        }
        return false;
    }
}
