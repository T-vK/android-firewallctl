/*
 * Background allow + UI feedback for notification / activity trampolines.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.content.Context;
import android.content.BroadcastReceiver;
import android.os.Handler;
import android.os.Looper;

final class AllowWorker implements Runnable {

    private final Context appContext;
    private final Activity activity;
    private final String pkg;
    private final BroadcastReceiver.PendingResult pendingResult;

    AllowWorker(Context appContext, String pkg, BroadcastReceiver.PendingResult pendingResult) {
        this.appContext = appContext;
        this.activity = null;
        this.pkg = pkg;
        this.pendingResult = pendingResult;
    }

    AllowWorker(Activity activity, String pkg) {
        this.appContext = activity.getApplicationContext();
        this.activity = activity;
        this.pkg = pkg;
        this.pendingResult = null;
    }

    @Override
    public void run() {
        boolean ok = AllowHelper.allowPackage(pkg);
        Handler main = new Handler(Looper.getMainLooper());
        if (activity != null) {
            main.post(new AllowUiDone(activity, pkg, ok));
        } else {
            main.post(new AllowUiDone(appContext, pkg, ok, pendingResult));
        }
    }
}
