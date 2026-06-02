/*
 * Legacy trampoline for allow network (prefer AllowReceiver from notifications).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.os.Bundle;

public final class AllowActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String pkg = getIntent().getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg == null || pkg.isEmpty()) {
            finish();
            return;
        }
        Thread t = new Thread(new AllowWorker(this, pkg), "firewall-allow");
        t.start();
    }
}
