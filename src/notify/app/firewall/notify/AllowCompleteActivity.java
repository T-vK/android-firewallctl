/*
 * Trampoline started by the root watcher to signal allow success in-process.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.os.Bundle;

public final class AllowCompleteActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String pkg = getIntent().getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg != null && !pkg.isEmpty()) {
            AllowCompleteReceiver.signalComplete(pkg);
            AllowHelper.clearCompleteMarker(getApplicationContext());
        }
        finish();
    }
}
