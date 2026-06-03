/*
 * Allow-complete latch (broadcast, activity, or cache marker from root watcher).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public final class AllowCompleteReceiver extends BroadcastReceiver {

    public static final String ACTION_ALLOW_COMPLETE = "app.firewall.notify.ALLOW_COMPLETE";

    private static final Object LOCK = new Object();
    private static String pendingPkg;
    private static CountDownLatch pendingLatch;

    static void beginWait(String pkg) {
        synchronized (LOCK) {
            pendingPkg = pkg;
            pendingLatch = new CountDownLatch(1);
        }
    }

    static boolean awaitComplete(Context ctx, String pkg, int timeoutMs) {
        File marker = AllowHelper.completeMarkerFile(ctx);
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (System.currentTimeMillis() < deadline) {
            if (pkg.equals(readMarkerPackage(marker))) {
                AllowHelper.clearCompleteMarker(ctx);
                clear();
                return true;
            }
            CountDownLatch latch;
            synchronized (LOCK) {
                if (pendingLatch == null || pendingPkg == null || !pendingPkg.equals(pkg)) {
                    return false;
                }
                latch = pendingLatch;
            }
            try {
                if (latch.await(200, TimeUnit.MILLISECONDS)) {
                    clear();
                    return true;
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                clear();
                return false;
            }
        }
        clear();
        return false;
    }

    static void clear() {
        synchronized (LOCK) {
            pendingPkg = null;
            pendingLatch = null;
        }
    }

    static void signalComplete(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return;
        }
        synchronized (LOCK) {
            if (pendingLatch != null && pkg.equals(pendingPkg)) {
                pendingLatch.countDown();
            }
        }
    }

    private static String readMarkerPackage(File marker) {
        if (marker == null || !marker.isFile()) {
            return null;
        }
        try (BufferedReader br = new BufferedReader(new FileReader(marker))) {
            String line = br.readLine();
            return line != null ? line.trim() : null;
        } catch (Throwable ignored) {
            return null;
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !ACTION_ALLOW_COMPLETE.equals(intent.getAction())) {
            return;
        }
        signalComplete(intent.getStringExtra(NotifyHelper.EXTRA_PACKAGE));
    }
}
