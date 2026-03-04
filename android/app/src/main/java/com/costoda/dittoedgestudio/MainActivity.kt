package com.costoda.dittoedgestudio

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.costoda.dittoedgestudio.ui.navigation.AppNavGraph
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            EdgeStudioTheme {
                AppNavGraph()
            }
        }
    }
}
