package com.edgestudio

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import com.edgestudio.data.initializeAndroidContext
import com.ditto.kotlin.transports.DittoSyncPermissions

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        
        // Initialize Android context for Ditto
        initializeAndroidContext(this)
        setContent {
            App()
        }
        requestMissingPermissions()
    }

    private fun requestMissingPermissions() {
        val missingPermissions = DittoSyncPermissions(this).missingPermissions()
        if (missingPermissions.isNotEmpty()) {
            this.requestPermissions(missingPermissions, 0)
        }
    }
}

@Preview
@Composable
fun AppAndroidPreview() {
    App()
}