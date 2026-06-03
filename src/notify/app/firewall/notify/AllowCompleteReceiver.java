/*
 * Legacy broadcast target for root watcher (optional; allow uses Magisk su now).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class AllowCompleteReceiver extends BroadcastReceiver {

    public static final String ACTION_ALLOW_COMPLETE = "app.firewall.notify.ALLOW_COMPLETE";

    static void signalComplete(String pkg) {
        /* no-op: allow path is synchronous via Magisk su */
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        /* no-op */
    }
}
