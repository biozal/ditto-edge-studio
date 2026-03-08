package com.costoda.dittoedgestudio.ui.mainstudio

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.ActivityCompat
import android.content.pm.PackageManager

@Composable
fun DittoPermissionHandler() {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        // Ditto and WifiManager pick up permission changes automatically
    }

    LaunchedEffect(Unit) {
        val missing = buildList {
            // Bluetooth permissions (API 31+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(
                        context, Manifest.permission.BLUETOOTH_SCAN,
                    ) != PackageManager.PERMISSION_GRANTED
                ) add(Manifest.permission.BLUETOOTH_SCAN)
                if (ActivityCompat.checkSelfPermission(
                        context, Manifest.permission.BLUETOOTH_CONNECT,
                    ) != PackageManager.PERMISSION_GRANTED
                ) add(Manifest.permission.BLUETOOTH_CONNECT)
                if (ActivityCompat.checkSelfPermission(
                        context, Manifest.permission.BLUETOOTH_ADVERTISE,
                    ) != PackageManager.PERMISSION_GRANTED
                ) add(Manifest.permission.BLUETOOTH_ADVERTISE)
            }

            // WiFi / SSID permissions
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ActivityCompat.checkSelfPermission(
                        context, Manifest.permission.NEARBY_WIFI_DEVICES,
                    ) != PackageManager.PERMISSION_GRANTED
                ) add(Manifest.permission.NEARBY_WIFI_DEVICES)
            } else {
                if (ActivityCompat.checkSelfPermission(
                        context, Manifest.permission.ACCESS_FINE_LOCATION,
                    ) != PackageManager.PERMISSION_GRANTED
                ) add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }
        if (missing.isNotEmpty()) {
            launcher.launch(missing.toTypedArray())
        }
    }
}
