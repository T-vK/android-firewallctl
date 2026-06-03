/*
 * Started by firewall-watcher to post a notification in a proper Activity context.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.os.Bundle;

public final class PostNotificationActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String pkg = getIntent().getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg != null && !pkg.isEmpty()) {
            String kind = getIntent().getStringExtra(NotifyHelper.EXTRA_KIND);
            if (NotifyHelper.KIND_INSTALL_DETECT.equals(kind)) {
                String when = getIntent().getStringExtra(NotifyHelper.EXTRA_WHEN);
                NotifyHelper.showInstallDetected(getApplicationContext(), pkg, when);
            } else {
                NotifyHelper.showBlocked(getApplicationContext(), pkg);
            }
        }
        finish();
    }
}
