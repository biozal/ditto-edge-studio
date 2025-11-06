package com.edgestudio.di

import com.edgestudio.data.IDittoManager
import com.edgestudio.data.repositories.IDatabaseRepository
import org.koin.core.annotation.KoinExperimentalAPI
import org.koin.test.verify.verify
import kotlin.test.Test

/**
 * Tests for Koin module configuration
 *
 * These tests verify that:
 * - All dependencies can be resolved
 * - The dependency graph is correctly configured
 * - No circular dependencies exist
 */
class AppModuleTest {

    @OptIn(KoinExperimentalAPI::class)
    @Test
    fun `verify dataModule configuration`() {
        // Verify that the data module is properly configured
        // This will check that all definitions can be created
        dataModule.verify(
            extraTypes = listOf(
                IDittoManager::class,
                IDatabaseRepository::class
            )
        )
    }

    @Test
    fun `appModules returns correct list of modules`() {
        val modules = appModules()

        assert(modules.isNotEmpty()) { "App modules should not be empty" }
        assert(modules.contains(dataModule)) { "App modules should contain dataModule" }
    }

    // Note: Full integration tests with actual Koin context startup would require
    // platform-specific setup for Ditto SDK initialization. These tests verify
    // the module structure and configuration.
}
