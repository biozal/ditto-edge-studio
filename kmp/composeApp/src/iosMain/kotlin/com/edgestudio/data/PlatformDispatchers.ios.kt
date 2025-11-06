package com.edgestudio.data

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

/**
 * iOS implementation of PlatformDispatchers.
 * Note: Dispatchers.IO is internal on native platforms, so we use Dispatchers.Default instead.
 */
actual object PlatformDispatchers {
    // On iOS, Dispatchers.IO is internal, so we use Default for IO operations
    actual val io: CoroutineDispatcher = Dispatchers.Default
    actual val default: CoroutineDispatcher = Dispatchers.Default
}
