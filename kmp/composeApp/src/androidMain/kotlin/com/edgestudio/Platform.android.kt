package com.edgestudio

import android.os.Build

class AndroidPlatform : Platform {
    override val name: String = "Android ${Build.VERSION.SDK_INT}"
}

actual fun getPlatform(): Platform = AndroidPlatform()

actual fun getAppDataDirectory(): String {
    // For Android, you typically need a Context
    // This assumes you have a way to get the application context
    val context = AndroidContextProvider.applicationContext

    // Internal app data directory (private to your app)
    return context.filesDir.absolutePath

}