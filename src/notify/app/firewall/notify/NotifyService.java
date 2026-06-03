/*
 * Foreground-service path for reliable block notifications from background.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;

public final class NotifyService extends Service {

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            stopSelf(startId);
            return START_NOT_STICKY;
        }
        String pkg = intent.getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg == null || pkg.isEmpty()) {
            stopSelf(startId);
            return START_NOT_STICKY;
        }
        try {
            NotifyHelper.showBlockedForeground(this, pkg);
            System.out.println("NotifyService: foreground posted for " + pkg);
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.err.println("NotifyService: " + c.getClass().getSimpleName() + ": " + c.getMessage());
        }
        stopSelf(startId);
        return START_NOT_STICKY;
    }
}
