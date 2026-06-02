/*
 * BroadcastReceiver for notification action buttons (compile-only android.jar).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewallctl;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class NotifyReceiver extends BroadcastReceiver {

    public interface Callback {
        void onAction(String action, String packageName);
    }

    private final String expectedAction;
    private final Callback callback;

    public NotifyReceiver(String expectedAction, Callback callback) {
        this.expectedAction = expectedAction;
        this.callback = callback;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (callback == null || intent == null) {
            return;
        }
        if (!expectedAction.equals(intent.getAction())) {
            return;
        }
        String pkg = intent.getStringExtra(BlockedAppNotifier.EXTRA_PACKAGE);
        callback.onAction(expectedAction, pkg);
    }
}
