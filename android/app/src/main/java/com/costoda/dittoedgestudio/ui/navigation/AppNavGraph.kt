package com.costoda.dittoedgestudio.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.costoda.dittoedgestudio.ui.database.DatabaseEditorScreen
import com.costoda.dittoedgestudio.ui.database.DatabaseListScreen
import com.costoda.dittoedgestudio.ui.mainstudio.MainStudioScreen
import com.costoda.dittoedgestudio.ui.qrcode.QrScannerScreen

sealed class Screen(val route: String) {
    object DatabaseList : Screen("database_list")
    object DatabaseEditor : Screen("database_editor?id={id}") {
        fun createRoute(id: Long = -1L) = "database_editor?id=$id"
    }
    object MainStudio : Screen("main_studio/{databaseId}") {
        fun createRoute(databaseId: Long) = "main_studio/$databaseId"
    }
    object QrScanner : Screen("qr_scanner")
}

@Composable
fun AppNavGraph() {
    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = Screen.DatabaseList.route,
    ) {
        composable(Screen.DatabaseList.route) {
            DatabaseListScreen(
                onAddDatabase = {
                    navController.navigate(Screen.DatabaseEditor.createRoute())
                },
                onEditDatabase = { database ->
                    navController.navigate(Screen.DatabaseEditor.createRoute(database.id))
                },
                onOpenDatabase = { database ->
                    navController.navigate(Screen.MainStudio.createRoute(database.id))
                },
                onScanQrCode = {
                    navController.navigate(Screen.QrScanner.route)
                },
            )
        }

        composable(
            route = Screen.DatabaseEditor.route,
            arguments = listOf(
                navArgument("id") {
                    type = NavType.LongType
                    defaultValue = -1L
                },
            ),
        ) { backStackEntry ->
            val id = backStackEntry.arguments?.getLong("id") ?: -1L
            DatabaseEditorScreen(
                databaseId = id,
                onDismiss = { navController.popBackStack() },
            )
        }

        composable(
            route = Screen.MainStudio.route,
            arguments = listOf(
                navArgument("databaseId") { type = NavType.LongType },
            ),
        ) { backStackEntry ->
            val dbId = backStackEntry.arguments?.getLong("databaseId") ?: -1L
            MainStudioScreen(
                databaseId = dbId,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Screen.QrScanner.route) {
            QrScannerScreen(
                onNavigateBack = { navController.popBackStack() },
            )
        }
    }
}
