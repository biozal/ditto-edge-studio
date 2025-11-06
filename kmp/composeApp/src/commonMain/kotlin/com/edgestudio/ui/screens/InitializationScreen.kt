package com.edgestudio.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.edgestudio.data.IDittoManager
import kotlinx.coroutines.launch
import org.koin.compose.koinInject

/**
 * Sealed class representing the initialization state of the Ditto database
 */
sealed class InitState {
    data object Loading : InitState()
    data object Success : InitState()
    data class Error(val message: String) : InitState()
}

/**
 * InitializationScreen handles the initialization of DittoManager before showing the main UI.
 *
 * This screen:
 * - Injects IDittoManager using Koin
 * - Calls initializeDittoStore() on first composition
 * - Shows loading state while initializing
 * - Displays error messages via Snackbar if initialization fails
 * - Only renders AppContent when successfully initialized
 */
@Composable
fun InitializationScreen(
    content: @Composable () -> Unit
) {
    val dittoManager: IDittoManager = koinInject()
    val snackbarHostState = remember { SnackbarHostState() }
    var initState by remember { mutableStateOf<InitState>(InitState.Loading) }
    val scope = rememberCoroutineScope()

    // Initialize Ditto on first composition
    LaunchedEffect(Unit) {
        try {
            dittoManager.initializeDittoStore()

            // Wait a moment for initialization to complete
            kotlinx.coroutines.delay(500)

            // Verify initialization succeeded
            if (dittoManager.isDittoLocalDatabaseInitialized()) {
                initState = InitState.Success
            } else {
                initState = InitState.Error("Failed to initialize Ditto: Database not initialized")
            }
        } catch (e: Exception) {
            initState = InitState.Error(e.message ?: "Unknown error during initialization")
        }
    }

    // Show Snackbar for errors
    LaunchedEffect(initState) {
        if (initState is InitState.Error) {
            snackbarHostState.showSnackbar(
                message = (initState as InitState.Error).message,
                duration = SnackbarDuration.Long
            )
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentAlignment = Alignment.Center
        ) {
            when (initState) {
                is InitState.Loading -> {
                    LoadingView()
                }
                is InitState.Success -> {
                    content()
                }
                is InitState.Error -> {
                    ErrorView(
                        error = (initState as InitState.Error).message,
                        onRetry = {
                            scope.launch {
                                initState = InitState.Loading
                                try {
                                    dittoManager.initializeDittoStore()
                                    kotlinx.coroutines.delay(500)
                                    if (dittoManager.isDittoLocalDatabaseInitialized()) {
                                        initState = InitState.Success
                                    } else {
                                        initState = InitState.Error("Failed to initialize Ditto: Database not initialized")
                                    }
                                } catch (e: Exception) {
                                    initState = InitState.Error(e.message ?: "Unknown error during initialization")
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

/**
 * Loading view shown during initialization
 */
@Composable
private fun LoadingView() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        CircularProgressIndicator()
        Text(
            text = "Initializing Ditto Edge Studio...",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onBackground
        )
    }
}

/**
 * Error view shown when initialization fails
 */
@Composable
private fun ErrorView(
    error: String,
    onRetry: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Initialization Failed",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.error
        )

        Text(
            text = error,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center
        )

        Button(
            onClick = onRetry,
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary
            )
        ) {
            Text("Retry")
        }
    }
}
