/*
 * Posts a notification via app_process: starts NotifyService (foreground) in-app.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Looper;

public final class NotifyRunner {

    private static final String PACKAGE = "app.firewall.notify";
    private static final int CONTEXT_INCLUDE_CODE = 0x00000001;
    private static final int CONTEXT_IGNORE_SECURITY = 0x00000002;

    private NotifyRunner() {
    }

    public static void main(String[] args) {
        if (args.length < 1 || args[0].isEmpty()) {
            System.err.println("NotifyRunner: missing package argument");
            System.exit(2);
        }
        try {
            Looper.prepareMainLooper();
            grantNotificationPermission();
            Context ctx = getAppContext();
            NotificationManager nm =
                    (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null && !nm.areNotificationsEnabled()) {
                grantNotificationPermission();
                if (!nm.areNotificationsEnabled()) {
                    System.err.println("NotifyRunner: POST_NOTIFICATIONS not granted");
                    System.exit(1);
                }
            }
            NotifyHelper.ensureChannel(nm);

            String pkg = args[0];
            if (args.length >= 2 && NotifyHelper.KIND_INSTALL_DETECT.equals(args[1])) {
                NotifyHelper.showInstallDetected(ctx, pkg, null);
                System.out.println("NotifyRunner: install_detect posted for " + pkg);
                System.exit(0);
            }

            Intent svc = new Intent(ctx, NotifyService.class);
            svc.putExtra(NotifyHelper.EXTRA_PACKAGE, pkg);
            svc.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(svc);
            } else {
                ctx.startService(svc);
            }

            if (NotifyHelper.waitForBlockedNotificationActive(nm, pkg)) {
                System.out.println("NotifyRunner: posted for " + pkg);
                System.exit(0);
            }
            System.err.println("NotifyRunner: service started but notification not active");
            System.exit(1);
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.err.println("NotifyRunner: " + c.getClass().getSimpleName() + ": " + c.getMessage());
            System.exit(1);
        }
    }

    private static void grantNotificationPermission() {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{
                    "/system/bin/pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS"});
            p.waitFor();
            Process p2 = Runtime.getRuntime().exec(new String[]{
                    "/system/bin/cmd", "appops", "set", PACKAGE, "POST_NOTIFICATION", "allow"});
            p2.waitFor();
        } catch (Throwable ignored) {
            /* best-effort */
        }
    }

    private static Context getAppContext() throws Exception {
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context system = (Context) at.getMethod("getSystemContext").invoke(thread);
        int flags = CONTEXT_INCLUDE_CODE | CONTEXT_IGNORE_SECURITY;
        return system.createPackageContext(PACKAGE, flags);
    }
}
