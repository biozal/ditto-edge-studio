package com.edgestudio.data

import kotlinx.coroutines.CoroutineDispatcher

/**
 * Platform-specific dispatcher provider.
 * Provides access to dispatchers that may have different implementations across platforms.
 */
expect object PlatformDispatchers {
    /**
     * Dispatcher optimized for IO operations.
     * - On JVM/Android: Returns Dispatchers.IO
     * - On Native (iOS): Returns Dispatchers.Default (IO is internal on native platforms)
     */
    val io: CoroutineDispatcher

    /**
     * Default dispatcher for CPU-intensive operations.
     * Returns Dispatchers.Default on all platforms.
     */
    val default: CoroutineDispatcher
}
