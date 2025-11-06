package com.edgestudio.data

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * Android implementation of PlatformDispatchers.
 * Provides access to Android-specific dispatchers including Dispatchers.IO.
 */
actual object PlatformDispatchers {
    actual val io: CoroutineDispatcher = Dispatchers.IO
    actual val default: CoroutineDispatcher = Dispatchers.Default
}
