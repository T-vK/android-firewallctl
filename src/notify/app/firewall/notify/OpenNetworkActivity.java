/*
 * Transparent trampoline: open per-app network / data settings.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

public final class OpenNetworkActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String pkg = getIntent().getStringExtra(NotifyHelper.EXTRA_PACKAGE);
        if (pkg != null && !pkg.isEmpty()) {
            try {
                Intent intent = NotifyHelper.buildDataSettingsIntent(this, pkg);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(intent);
            } catch (Throwable ignored) {
                /* no handler */
            }
        }
        finish();
    }
}
