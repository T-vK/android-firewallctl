/*
 * Posts actionable notifications for newly default-denied apps.
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;

public final class NotifyHelper {

    public static final String ACTION_SHOW_BLOCKED = "app.firewall.notify.SHOW_BLOCKED";
    public static final String EXTRA_PACKAGE = "package";
    public static final String EXTRA_KIND = "kind";
    public static final String EXTRA_WHEN = "when";
    public static final String KIND_INSTALL_DETECT = "install_detect";

    /** v2 channel: heads-up, sound, bypass DND; user may need to re-enable after upgrade. */
    private static final String CHANNEL_ID = "firewall_block_alert_v2";
    private static final String CHANNEL_NAME = "New app blocked (urgent)";
    private static final int NOTIFICATION_ID = 0x464444;
    private static final int INSTALL_DETECT_NOTIFICATION_ID = 0x464445;
    private static final int FLAG_IMMUTABLE = 0x04000000;

    private NotifyHelper() {
    }

    public static void showBlocked(Context context, String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return;
        }
        NotificationManager nm =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return;
        }
        ensureChannel(nm);

        String label = resolveAppLabel(context, pkg);
        String title = "Internet blocked for new app";
        String text = label + " — network access was disabled by default.";
        String tag = notificationTag(pkg);

        int iconId = android.R.drawable.stat_sys_warning;
        if (iconId == 0) {
            iconId = android.R.drawable.ic_dialog_alert;
        }

        int flags = PendingIntent.FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE;
        PendingIntent settingsPi = PendingIntent.getActivity(
                context, pkg.hashCode() + 1, openNetworkIntent(context, pkg), flags);
        PendingIntent allowPi = PendingIntent.getActivity(
                context, pkg.hashCode() + 2, allowIntent(context, pkg), flags);

        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(iconId)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(
                        text + "\n\nPackage: " + pkg))
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(false)
                .setDefaults(Notification.DEFAULT_ALL)
                .setContentIntent(settingsPi)
                .addAction(new Notification.Action.Builder(0, "Allow network", allowPi).build())
                .addAction(new Notification.Action.Builder(0, "Network settings", settingsPi)
                        .build());

        try {
            nm.notify(tag, NOTIFICATION_ID, builder.build());
        } catch (Throwable e) {
            System.err.println("FirewallNotify: notify failed: "
                    + e.getClass().getSimpleName() + ": " + e.getMessage());
            throw new RuntimeException(e);
        }
    }

    /** Visible notification for install-detect benchmark (not a block alert). */
    public static void showInstallDetected(Context context, String pkg, String when) {
        if (pkg == null || pkg.isEmpty()) {
            return;
        }
        NotificationManager nm =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return;
        }
        ensureChannel(nm);

        String label = resolveAppLabel(context, pkg);
        String title = "New user app installed";
        String time = when != null && !when.isEmpty() ? when : "";
        String text = time.isEmpty() ? label : time + " - " + label;
        String tag = "install_detect_" + pkg;

        int iconId = android.R.drawable.stat_notify_more;
        if (iconId == 0) {
            iconId = android.R.drawable.ic_dialog_alert;
        }

        int flags = PendingIntent.FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE;
        Intent details = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        details.setData(Uri.parse("package:" + pkg));
        details.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent settingsPi = PendingIntent.getActivity(
                context, pkg.hashCode() + 200, details, flags);

        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(iconId)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text + "\n\nPackage: " + pkg))
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setContentIntent(settingsPi);

        try {
            nm.notify(tag, INSTALL_DETECT_NOTIFICATION_ID, builder.build());
        } catch (Throwable e) {
            System.err.println("FirewallNotify: install_detect notify failed: "
                    + e.getClass().getSimpleName() + ": " + e.getMessage());
            throw new RuntimeException(e);
        }
    }

    public static void cancel(Context context, String pkg) {
        if (context == null || pkg == null || pkg.isEmpty()) {
            return;
        }
        Context app = context.getApplicationContext();
        NotificationManager nm =
                (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.cancel(notificationTag(pkg), NOTIFICATION_ID);
        }
    }

    public static String notificationTag(String pkg) {
        return "firewall_default_deny_" + pkg;
    }

    private static void ensureChannel(NotificationManager nm) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        int importance = channelImportance();
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, importance);
        channel.setDescription("Immediate alert when a new app is blocked by default");
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        channel.enableVibration(true);
        channel.enableLights(true);
        channel.setBypassDnd(true);
        Uri sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        if (sound != null) {
            channel.setSound(
                    sound,
                    new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build());
        }
        nm.createNotificationChannel(channel);
    }

    private static int channelImportance() {
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                return NotificationManager.class.getField("IMPORTANCE_MAX").getInt(null);
            } catch (Throwable ignored) {
                /* fall through */
            }
        }
        return NotificationManager.IMPORTANCE_HIGH;
    }

    static Intent allowIntent(Context context, String pkg) {
        Intent intent = new Intent(context, AllowActivity.class);
        intent.putExtra(EXTRA_PACKAGE, pkg);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    static Intent openNetworkIntent(Context context, String pkg) {
        Intent intent = new Intent(context, OpenNetworkActivity.class);
        intent.putExtra(EXTRA_PACKAGE, pkg);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    /** Opens per-app Mobile data and Wi-Fi / data usage (not app-info parent screen). */
    static Intent buildDataSettingsIntent(Context context, String pkg) {
        Uri packageUri = Uri.parse("package:" + pkg);
        ComponentName appDataUsage = new ComponentName(
                "com.android.settings",
                "com.android.settings.datausage.AppDataUsageActivity");

        Intent[] candidates = new Intent[] {
                new Intent("android.settings.IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS")
                        .setData(packageUri)
                        .setComponent(appDataUsage),
                new Intent("android.settings.IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS")
                        .setData(packageUri),
                new Intent(Intent.ACTION_MANAGE_NETWORK_USAGE)
                        .setData(packageUri)
                        .addCategory(Intent.CATEGORY_DEFAULT),
                new Intent("android.settings.APP_DATA_USAGE")
                        .setData(packageUri)
                        .putExtra("android.intent.extra.PACKAGE_NAME", pkg),
                new Intent("android.settings.APPLICATION_DETAILS_SETTINGS")
                        .setData(packageUri),
        };
        PackageManager pm = context.getPackageManager();
        for (Intent intent : candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (intent.resolveActivity(pm) != null) {
                return intent;
            }
        }
        Intent fallback = candidates[0];
        fallback.setComponent(appDataUsage);
        return fallback;
    }

    private static String resolveAppLabel(Context context, String pkg) {
        try {
            PackageManager pm = context.getPackageManager();
            ApplicationInfo info = pm.getApplicationInfo(pkg, 0);
            return String.valueOf(info.loadLabel(pm));
        } catch (Throwable ignored) {
            return pkg;
        }
    }
}
