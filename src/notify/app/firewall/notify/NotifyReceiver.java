/*
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class NotifyReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        final PendingResult pending = goAsync();
        try {
            if (intent == null) {
                return;
            }
            if (!NotifyHelper.ACTION_SHOW_BLOCKED.equals(intent.getAction())) {
                return;
            }
            String pkg = intent.getStringExtra(NotifyHelper.EXTRA_PACKAGE);
            if (pkg == null || pkg.isEmpty()) {
                return;
            }
            Context app = context.getApplicationContext();
            String kind = intent.getStringExtra(NotifyHelper.EXTRA_KIND);
            if (NotifyHelper.KIND_INSTALL_DETECT.equals(kind)) {
                String when = intent.getStringExtra(NotifyHelper.EXTRA_WHEN);
                NotifyHelper.showInstallDetected(app, pkg, when);
            } else {
                NotifyHelper.showBlocked(app, pkg);
            }
        } finally {
            pending.finish();
        }
    }
}
