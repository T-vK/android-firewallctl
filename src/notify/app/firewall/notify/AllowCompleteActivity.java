/*
 * Legacy trampoline from root watcher (optional).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Activity;
import android.os.Bundle;

public final class AllowCompleteActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        finish();
    }
}
