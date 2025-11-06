package com.edgestudio

import platform.UIKit.UIDevice
import platform.Foundation.NSApplicationSupportDirectory
import platform.Foundation.NSSearchPathForDirectoriesInDomains
import platform.Foundation.NSUserDomainMask

class IOSPlatform : Platform {
    override val name: String = UIDevice.currentDevice.systemName() + " " + UIDevice.currentDevice.systemVersion
}

actual fun getPlatform(): Platform = IOSPlatform()

actual fun getAppDataDirectory(): String {
    val appSupportDirectory = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory,
        NSUserDomainMask,
        true
    ).firstOrNull() as? String

    return appSupportDirectory ?: throw IllegalStateException("Cannot access application support directory")
}