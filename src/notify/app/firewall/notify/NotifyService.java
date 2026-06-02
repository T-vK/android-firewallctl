/*
 * Started by firewall-watcher to post a notification without launching an Activity.
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
        if (intent != null) {
            String pkg = intent.getStringExtra(NotifyHelper.EXTRA_PACKAGE);
            if (pkg != null && !pkg.isEmpty()) {
                NotifyHelper.showBlocked(getApplicationContext(), pkg);
            }
        }
        stopSelf(startId);
        return START_NOT_STICKY;
    }
}
