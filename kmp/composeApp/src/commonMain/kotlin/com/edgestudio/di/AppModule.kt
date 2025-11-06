package com.edgestudio.di

import com.edgestudio.data.CoroutineScopeProvider
import com.edgestudio.data.DittoManager
import com.edgestudio.data.IDittoManager
import com.edgestudio.data.ProductionCoroutineScopeProvider
import com.edgestudio.data.repositories.DatabaseRepository
import com.edgestudio.data.repositories.IDatabaseRepository
import org.koin.core.module.dsl.singleOf
import org.koin.dsl.bind
import org.koin.dsl.module

/**
 * Data module containing repositories and managers
 * Uses single scope for singleton instances that live for the app lifetime
 */
val dataModule = module {
    // Provide CoroutineScopeProvider for the application
    single<CoroutineScopeProvider> { ProductionCoroutineScopeProvider() }

    // DittoManager - single instance for the entire app, with injected scope provider
    single<IDittoManager> { DittoManager(scopeProvider = get()) }

    // DatabaseRepository - depends on IDittoManager
    single<IDatabaseRepository> { DatabaseRepository(get()) }
}

/**
 * Helper function to gather all modules
 * Makes it easy to add more modules as the app grows (e.g., viewModelModule, networkModule)
 */
fun appModules() = listOf(dataModule)
