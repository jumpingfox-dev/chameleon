package dev.jumpingfox.chameleon

import android.app.Activity
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Turns the screen off when the screensaver's time is up (Settings › Screensaver › Turn off the
 * TV). Apps can't power a TV off themselves; locking the device turns its screen off, and a TV
 * set to follow its source over HDMI-CEC then goes to standby.
 *
 * Locking needs the person's OK once, as a device admin that may only lock the screen
 * (res/xml/screen_off_admin.xml). Turning the setting off gives that back, since Android won't
 * uninstall an app that's still a device admin.
 */
class ScreenOff(private val activity: Activity, messenger: BinaryMessenger) {
    private val policy = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    private val admin = ComponentName(activity, Admin::class.java)
    private var pendingEnable: MethodChannel.Result? = null

    /** Has to be declared in the manifest; does nothing itself. */
    class Admin : DeviceAdminReceiver()

    init {
        MethodChannel(messenger, "chameleon/screen_off").setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(policy.isAdminActive(admin))
                "enable" -> enable(result)
                "disable" -> {
                    if (policy.isAdminActive(admin)) policy.removeActiveAdmin(admin)
                    result.success(null)
                }
                "turnOff" -> {
                    if (policy.isAdminActive(admin)) {
                        policy.lockNow()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Asks for the OK, and answers with whether it was given. */
    private fun enable(result: MethodChannel.Result) {
        if (policy.isAdminActive(admin)) return result.success(true)
        pendingEnable?.success(false)
        pendingEnable = result
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
            .putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Lets Chameleon turn the screen off when the screensaver's time is up. It can't do anything else.",
            )
        try {
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: Exception) {
            pendingEnable = null
            result.error("unavailable", "This device can't grant that permission: ${e.message}", null)
        }
    }

    /** From MainActivity, when the permission screen closes. */
    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        pendingEnable?.success(policy.isAdminActive(admin))
        pendingEnable = null
        return true
    }

    companion object {
        private const val REQUEST = 4207
    }
}
