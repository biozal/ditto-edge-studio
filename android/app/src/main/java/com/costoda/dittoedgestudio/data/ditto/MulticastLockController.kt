package com.costoda.dittoedgestudio.data.ditto

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig

/**
 * Holds a process-level [WifiManager.MulticastLock] for as long as the multicast
 * (beta) transport is enabled.
 *
 * The Ditto SDK acquires its own engine-level lock, but the app-level lock (same
 * pattern as the Zava Retail demo) keeps multicast delivery alive process-wide for
 * the whole enabled period. The lock is non-reference-counted and acquire/release
 * are guarded by [WifiManager.MulticastLock.isHeld], so repeated applies are safe.
 */
class MulticastLockController(private val appContext: Context) {

    private var lock: WifiManager.MulticastLock? = null

    @Synchronized
    fun acquire() {
        if (lock == null) {
            @Suppress("DEPRECATION") // WIFI_SERVICE lookup is the supported path for MulticastLock
            lock = (appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager)
                ?.createMulticastLock(LOCK_TAG)
                ?.apply { setReferenceCounted(false) }
        }
        val held = lock?.isHeld == true
        if (!held) {
            runCatching { lock?.acquire() }
                .onFailure { e ->
                    if (BuildConfig.DEBUG) {
                        Log.w(TAG, "Failed to acquire multicast lock: ${e.message}")
                    }
                }
        }
    }

    @Synchronized
    fun release() {
        lock?.let { if (it.isHeld) runCatching { it.release() } }
    }

    companion object {
        private const val TAG = "MulticastLockController"
        private const val LOCK_TAG = "edge-studio-multicast"
    }
}
