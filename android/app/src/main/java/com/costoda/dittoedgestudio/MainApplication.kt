package com.costoda.dittoedgestudio

import android.app.Application
import com.costoda.dittoedgestudio.data.di.dataModule
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Load SQLCipher native library before any database operations
        System.loadLibrary("sqlcipher")
        startKoin {
            androidLogger()
            androidContext(this@MainApplication)
            modules(dataModule)
        }
    }
}
