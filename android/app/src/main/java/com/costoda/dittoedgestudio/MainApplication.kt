package com.costoda.dittoedgestudio

import android.app.Application
import com.costoda.dittoedgestudio.data.di.dataModule
import com.costoda.dittoedgestudio.data.logging.LoggingService
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import timber.log.Timber

class MainApplication : Application(), KoinComponent {
    override fun onCreate() {
        super.onCreate()
        // Load SQLCipher native library before any database operations
        System.loadLibrary("sqlcipher")
        startKoin {
            androidLogger()
            androidContext(this@MainApplication)
            modules(dataModule)
        }
        // Plant Timber file logging tree after Koin is initialized
        val loggingService: LoggingService by inject()
        loggingService.rotateOldLogs()
        Timber.plant(loggingService.createTree())
    }
}
