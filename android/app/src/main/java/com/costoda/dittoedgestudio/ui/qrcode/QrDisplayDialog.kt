package com.costoda.dittoedgestudio.ui.qrcode

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import org.koin.androidx.compose.koinViewModel
import org.koin.core.parameter.parametersOf

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QrDisplayDialog(
    database: DittoDatabase,
    onDismiss: () -> Unit,
    viewModel: QrDisplayViewModel = koinViewModel(parameters = { parametersOf(database) }),
) {
    val bitmap by viewModel.bitmap.collectAsState()
    val isError by viewModel.isError.collectAsState()
    val sheetState = rememberModalBottomSheetState()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = database.name,
                style = MaterialTheme.typography.titleLarge,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Scan with another device to import this database config",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary,
            )
            Spacer(modifier = Modifier.height(24.dp))

            Box(
                modifier = Modifier.size(250.dp),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    isError -> {
                        Text(
                            text = "Unable to generate QR code",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    bitmap != null -> {
                        Image(
                            bitmap = bitmap!!.asImageBitmap(),
                            contentDescription = "QR code for ${database.name}",
                            modifier = Modifier.size(250.dp),
                            contentScale = ContentScale.Fit,
                            filterQuality = FilterQuality.None,
                        )
                    }
                    else -> {
                        CircularProgressIndicator()
                    }
                }
            }
            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}
