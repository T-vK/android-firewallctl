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
            NotifyHelper.showBlocked(getApplicationContext(), pkg);
        }
        finish();
    }
}
