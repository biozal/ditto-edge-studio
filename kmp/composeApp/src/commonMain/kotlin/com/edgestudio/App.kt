package com.edgestudio

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.ui.tooling.preview.Preview

import dittoedgestudio.composeapp.generated.resources.Res
import dittoedgestudio.composeapp.generated.resources.compose_multiplatform
import com.edgestudio.ui.theme.DittoEdgeStudioTheme
import com.edgestudio.ui.theme.LocalThemeManager
import com.edgestudio.ui.theme.ThemeManager
import com.edgestudio.ui.components.ThemeToggleButton
import com.edgestudio.ui.components.QuickThemeToggle
import com.edgestudio.di.appModules
import com.edgestudio.ui.screens.InitializationScreen
import org.koin.compose.KoinApplication


@Composable
@Preview
fun App(
    modifier: Modifier = Modifier) {
    KoinApplication(
        application = {
            modules(appModules())
        }
    ) {
        val themeManager = remember { ThemeManager() }
        CompositionLocalProvider(LocalThemeManager provides themeManager) {
            DittoEdgeStudioTheme(
                darkTheme = themeManager.isDarkTheme()
            ) {
                InitializationScreen {
                    AppContent()
                }
            }
        }
    }
}

@Composable
private fun AppContent() {
    var showContent by remember { mutableStateOf(false) }
    
    // Cache expensive calculations and avoid recomposition during resize
    val backgroundColor = MaterialTheme.colorScheme.background
    val onBackgroundColor = MaterialTheme.colorScheme.onBackground
    
    Column(
        modifier = Modifier
            .background(backgroundColor)
            .safeContentPadding()
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header with theme controls
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Ditto Edge Studio",
                style = MaterialTheme.typography.headlineMedium,
                color = onBackgroundColor
            )
            
            QuickThemeToggle()
        }
        
        // Theme selector card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface
            )
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = "Theme Settings",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )
                
                ThemeToggleButton()
            }
        }
        
        // Original demo content
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer
            )
        ) {
            Column(
                modifier = Modifier.padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Button(
                    onClick = { showContent = !showContent },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary
                    )
                ) {
                    Text("Click me!")
                }
                
                AnimatedVisibility(showContent) {
                    val greeting = remember { Greeting().greet() }
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Image(
                            painter = painterResource(Res.drawable.compose_multiplatform),
                            contentDescription = "Compose Multiplatform",
                            modifier = Modifier.size(200.dp)
                        )
                        Text(
                            text = "Compose: $greeting",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    }
                }
            }
        }
        
        Spacer(modifier = Modifier.weight(1f))
        
        // Footer
        Text(
            text = "Material 3 • Light & Dark Theme Support • Ditto SDK Available",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}