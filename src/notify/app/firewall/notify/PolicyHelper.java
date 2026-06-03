/*
 * Applies NetworkPolicyManager changes (same Binder path as firewallctl).
 * Requires MANAGE_NETWORK_POLICY (granted via priv-app allowlist in the module).
 * SPDX-License-Identifier: Apache-2.0
 */
package app.firewall.notify;

import android.util.Log;

import java.io.BufferedReader;
import java.io.FileReader;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.LinkedHashMap;
import java.util.Map;

final class PolicyHelper {

    private static final String TAG = "FirewallNotify";
    private static final String SERVICE_NAME = "netpolicy";
    private static final String NPM_CLASS = "android.net.NetworkPolicyManager";
    private static final String INPM_STUB_CLASS = "android.net.INetworkPolicyManager$Stub";
    private static final String SERVICE_MANAGER_CLASS = "android.os.ServiceManager";
    private static final String IBINDER_CLASS = "android.os.IBinder";

    private static Object npm;
    private static Map<String, Integer> policies;
    private static Integer policyRejectAll;

    private PolicyHelper() {
    }

    /** Clear REJECT_ALL for pkg; returns true when policy no longer blocks all networks. */
    static boolean allowNetwork(String pkg) {
        if (pkg == null || pkg.isEmpty()) {
            return false;
        }
        try {
            connect();
            int uid = resolveUid(pkg);
            int rejectAll = policyRejectAll();
            int before = getUidPolicy(uid);
            if ((before & rejectAll) == 0) {
                Log.i(TAG, "policy allow " + pkg + " uid=" + uid + " already clear");
                return true;
            }
            int cleared = before & ~rejectAll;
            setUidPolicy(uid, cleared);
            int after = getUidPolicy(uid);
            boolean ok = (after & rejectAll) == 0;
            Log.i(TAG, "policy allow " + pkg + " uid=" + uid
                    + " before=0x" + Integer.toHexString(before)
                    + " after=0x" + Integer.toHexString(after) + " ok=" + ok);
            return ok;
        } catch (Throwable t) {
            Log.w(TAG, "policy allow failed for " + pkg + ": " + t.getMessage());
            return false;
        }
    }

    private static void connect() throws Exception {
        if (npm != null) {
            return;
        }
        relaxHiddenApi();
        Class<?> sm = Class.forName(SERVICE_MANAGER_CLASS);
        Object binder = sm.getMethod("getService", String.class).invoke(null, SERVICE_NAME);
        if (binder == null) {
            throw new RuntimeException("netpolicy service not available");
        }
        Class<?> ibinder = Class.forName(IBINDER_CLASS);
        Class<?> stub = Class.forName(INPM_STUB_CLASS);
        npm = stub.getMethod("asInterface", ibinder).invoke(null, binder);
        policies = new LinkedHashMap<>();
        Class<?> npmCls = Class.forName(NPM_CLASS);
        for (Field f : npmCls.getFields()) {
            if (f.getType() == int.class && Modifier.isStatic(f.getModifiers())
                    && f.getName().startsWith("POLICY_")) {
                policies.put(f.getName(), f.getInt(null));
            }
        }
        policyRejectAll = policies.get("POLICY_REJECT_ALL");
        if (policyRejectAll == null) {
            throw new RuntimeException("POLICY_REJECT_ALL not exposed on this ROM");
        }
    }

    private static int policyRejectAll() {
        return policyRejectAll;
    }

    private static int resolveUid(String pkg) throws Exception {
        try (BufferedReader br = new BufferedReader(new FileReader("/data/system/packages.list"))) {
            String line;
            while ((line = br.readLine()) != null) {
                int sp1 = line.indexOf(' ');
                if (sp1 < 0 || !pkg.equals(line.substring(0, sp1))) {
                    continue;
                }
                int sp2 = line.indexOf(' ', sp1 + 1);
                String uidStr = sp2 < 0 ? line.substring(sp1 + 1) : line.substring(sp1 + 1, sp2);
                return Integer.parseInt(uidStr);
            }
        }
        throw new RuntimeException("package not in packages.list: " + pkg);
    }

    private static int getUidPolicy(int uid) throws Exception {
        return (int) npm.getClass().getMethod("getUidPolicy", int.class).invoke(npm, uid);
    }

    private static void setUidPolicy(int uid, int policy) throws Exception {
        npm.getClass().getMethod("setUidPolicy", int.class, int.class).invoke(npm, uid, policy);
    }

    private static void relaxHiddenApi() {
        try {
            Method forName = Class.class.getDeclaredMethod(
                    "forName", String.class, boolean.class, ClassLoader.class);
            Class<?> vmRuntimeClass = (Class<?>) forName.invoke(
                    null, "dalvik.system.VMRuntime", true, ClassLoader.getSystemClassLoader());
            Method getRuntime = vmRuntimeClass.getDeclaredMethod("getRuntime");
            Object vmRuntime = getRuntime.invoke(null);
            Method setHiddenApiExemptions =
                    vmRuntimeClass.getDeclaredMethod("setHiddenApiExemptions", String[].class);
            setHiddenApiExemptions.invoke(vmRuntime, new Object[] {new String[] {"L"}});
        } catch (Throwable ignored) {
            /* best-effort */
        }
    }
}
