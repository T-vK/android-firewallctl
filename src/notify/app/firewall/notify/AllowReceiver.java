/*
 * Handles "Allow network" notification action (broadcast, not activity trampoline).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class AllowReceiver extends BroadcastReceiver {

    public static final String ACTION_ALLOW_NETWORK = "app.firewall.notify.ALLOW_NETWORK";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !ACTION_ALLOW_NETWORK.equals(intent.getAction())) {
            return;
        }
        String pkg = intent.getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg == null || pkg.isEmpty()) {
            return;
        }
        PendingResult result = goAsync();
        Thread t = new Thread(
                new AllowWorker(context.getApplicationContext(), pkg, result),
                "firewall-allow");
        t.start();
    }
}
