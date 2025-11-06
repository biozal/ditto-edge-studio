package com.edgestudio.data

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob

/**
 * Provider interface for CoroutineScopes and Dispatchers used throughout the application.
 * This abstraction allows for proper testing by enabling scope and dispatcher injection.
 */
interface CoroutineScopeProvider {
    /**
     * Application-level scope that should live for the entire app lifecycle.
     * Used by DittoManager for long-running operations.
     */
    val applicationScope: CoroutineScope

    /**
     * Default dispatcher for general coroutine operations.
     * Used for Ditto initialization (SDKS-1294: Don't create Ditto on Dispatchers.IO)
     */
    val defaultDispatcher: CoroutineDispatcher

    /**
     * IO dispatcher for blocking I/O operations.
     * Used for database close operations and cleanup.
     */
    val ioDispatcher: CoroutineDispatcher
}

/**
 * Production implementation of CoroutineScopeProvider.
 * Uses platform-specific dispatchers for production environments.
 */
class ProductionCoroutineScopeProvider : CoroutineScopeProvider {
    override val applicationScope: CoroutineScope =
        CoroutineScope(SupervisorJob() + PlatformDispatchers.default)

    override val defaultDispatcher: CoroutineDispatcher = PlatformDispatchers.default

    override val ioDispatcher: CoroutineDispatcher = PlatformDispatchers.io
}

/**
 * Test implementation of CoroutineScopeProvider.
 * Allows tests to inject a controlled scope and test dispatchers for deterministic testing.
 */
class TestCoroutineScopeProvider(
    testScope: CoroutineScope,
    testDispatcher: CoroutineDispatcher
) : CoroutineScopeProvider {
    override val applicationScope: CoroutineScope = testScope
    override val defaultDispatcher: CoroutineDispatcher = testDispatcher
    override val ioDispatcher: CoroutineDispatcher = testDispatcher
}
