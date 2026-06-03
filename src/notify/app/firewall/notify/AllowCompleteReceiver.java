/*
 * Root watcher signals allow success via am broadcast (no file read from app).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public final class AllowCompleteReceiver extends BroadcastReceiver {

    public static final String ACTION_ALLOW_COMPLETE = "app.firewall.notify.ALLOW_COMPLETE";

    private static final Object LOCK = new Object();
    private static String pendingPkg;
    private static CountDownLatch pendingLatch;

    private AllowCompleteReceiver() {
    }

    static void beginWait(String pkg) {
        synchronized (LOCK) {
            pendingPkg = pkg;
            pendingLatch = new CountDownLatch(1);
        }
    }

    static boolean awaitComplete(String pkg, int timeoutMs) {
        CountDownLatch latch;
        synchronized (LOCK) {
            if (pendingLatch == null || pendingPkg == null || !pendingPkg.equals(pkg)) {
                return false;
            }
            latch = pendingLatch;
        }
        try {
            return latch.await(timeoutMs, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        } finally {
            clear();
        }
    }

    static void clear() {
        synchronized (LOCK) {
            pendingPkg = null;
            pendingLatch = null;
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !ACTION_ALLOW_COMPLETE.equals(intent.getAction())) {
            return;
        }
        String pkg = intent.getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg == null || pkg.isEmpty()) {
            return;
        }
        synchronized (LOCK) {
            if (pendingLatch != null && pkg.equals(pendingPkg)) {
                pendingLatch.countDown();
            }
        }
    }
}
