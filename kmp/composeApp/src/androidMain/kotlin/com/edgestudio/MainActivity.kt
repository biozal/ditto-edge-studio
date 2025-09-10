package com.edgestudio

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import com.edgestudio.data.initializeAndroidContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        
        // Initialize Android context for Ditto
        initializeAndroidContext(this)
        AndroidContextProvider.initialize(this)
        setContent {
            App()
        }
    }
}

// In androidMain, create a context provider
object AndroidContextProvider {
    lateinit var applicationContext: Context

    fun initialize(context: Context) {
        applicationContext = context.applicationContext
    }
}

@Preview
@Composable
fun AppAndroidPreview() {
    App()
}