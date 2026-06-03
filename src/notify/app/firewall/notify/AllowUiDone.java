/*
 * Main-thread toast + finish after allow attempt.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.widget.Toast;

final class AllowUiDone implements Runnable {

    private final Context appContext;
    private final Activity activity;
    private final String pkg;
    private final boolean ok;
    private final BroadcastReceiver.PendingResult pendingResult;

    AllowUiDone(Context appContext, String pkg, boolean ok,
            BroadcastReceiver.PendingResult pendingResult) {
        this.appContext = appContext;
        this.activity = null;
        this.pkg = pkg;
        this.ok = ok;
        this.pendingResult = pendingResult;
    }

    AllowUiDone(Activity activity, String pkg, boolean ok) {
        this.appContext = activity.getApplicationContext();
        this.activity = activity;
        this.pkg = pkg;
        this.ok = ok;
        this.pendingResult = null;
    }

    @Override
    public void run() {
        Context ctx = activity != null ? activity : appContext;
        if (ok) {
            NotifyHelper.cancel(ctx, pkg);
            Toast.makeText(ctx, "Network allowed for " + pkg, Toast.LENGTH_SHORT).show();
        } else {
            Toast.makeText(ctx, "Could not allow network (queue failed)", Toast.LENGTH_LONG).show();
        }
        if (pendingResult != null) {
            pendingResult.finish();
        }
        if (activity != null && !activity.isFinishing()) {
            activity.finish();
        }
    }
}
