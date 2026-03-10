package com.costoda.dittoedgestudio.ui.database

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.ui.qrcode.QrDisplayDialog
import com.costoda.dittoedgestudio.ui.theme.EdgeStudioTheme
import com.costoda.dittoedgestudio.ui.theme.JetBlack
import com.costoda.dittoedgestudio.ui.theme.SulfurYellow
import com.costoda.dittoedgestudio.viewmodel.DatabaseListUiState
import com.costoda.dittoedgestudio.viewmodel.DatabaseListViewModel
import org.koin.androidx.compose.koinViewModel

@Composable
fun DatabaseListScreen(
    onAddDatabase: () -> Unit,
    onEditDatabase: (DittoDatabase) -> Unit,
    onOpenDatabase: (DittoDatabase) -> Unit,
    onScanQrCode: () -> Unit,
    viewModel: DatabaseListViewModel = koinViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val screenWidthDp = LocalConfiguration.current.screenWidthDp
    var tabletEditorId by remember { mutableStateOf<Long?>(null) }
    var tabletEditorSession by remember { mutableStateOf(0) }
    var showQrDialogFor by remember { mutableStateOf<DittoDatabase?>(null) }

    if (screenWidthDp >= 600) {
        TabletDatabaseListLayout(
            uiState = uiState,
            onAddDatabase = { tabletEditorId = -1L; tabletEditorSession++ },
            onEditDatabase = { db -> tabletEditorId = db.id; tabletEditorSession++ },
            onOpenDatabase = onOpenDatabase,
            onDeleteDatabase = { viewModel.deleteDatabase(it) },
            onShowQrCode = { db -> showQrDialogFor = db },
            onScanQrCode = onScanQrCode,
        )
        tabletEditorId?.let { id ->
            Dialog(
                onDismissRequest = { tabletEditorId = null },
                properties = DialogProperties(usePlatformDefaultWidth = false),
            ) {
                Surface(
                    modifier = Modifier
                        .width(560.dp)
                        .fillMaxHeight(0.85f),
                    shape = RoundedCornerShape(16.dp),
                    tonalElevation = 8.dp,
                ) {
                    DatabaseEditorScreen(
                        databaseId = id,
                        instanceKey = "tablet_editor_$tabletEditorSession",
                        onDismiss = { tabletEditorId = null },
                    )
                }
            }
        }
    } else {
        PhoneDatabaseListLayout(
            uiState = uiState,
            onAddDatabase = onAddDatabase,
            onEditDatabase = onEditDatabase,
            onOpenDatabase = onOpenDatabase,
            onDeleteDatabase = { viewModel.deleteDatabase(it) },
            onShowQrCode = { db -> showQrDialogFor = db },
            onScanQrCode = onScanQrCode,
        )
    }

    showQrDialogFor?.let { db ->
        QrDisplayDialog(
            database = db,
            onDismiss = { showQrDialogFor = null },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhoneDatabaseListLayout(
    uiState: DatabaseListUiState,
    onAddDatabase: () -> Unit,
    onEditDatabase: (DittoDatabase) -> Unit,
    onOpenDatabase: (DittoDatabase) -> Unit,
    onDeleteDatabase: (Long) -> Unit,
    onShowQrCode: (DittoDatabase) -> Unit,
    onScanQrCode: () -> Unit,
) {
    val context = LocalContext.current
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Edge Studio") },
                actions = {
                    IconButton(onClick = onScanQrCode) {
                        Icon(
                            imageVector = Icons.Outlined.QrCodeScanner,
                            contentDescription = "Scan QR Code",
                        )
                    }
                    IconButton(
                        onClick = {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://portal.ditto.live/"))
                            context.startActivity(intent)
                        },
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Cloud,
                            contentDescription = "Open Ditto Portal",
                        )
                    }
                },
                scrollBehavior = scrollBehavior,
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onAddDatabase,
                containerColor = SulfurYellow,
                contentColor = JetBlack,
            ) {
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = "Add database",
                )
            }
        },
    ) { paddingValues ->
        when (uiState) {
            is DatabaseListUiState.Loading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            is DatabaseListUiState.Empty -> {
                EmptyDatabasesView(
                    modifier = Modifier.padding(paddingValues),
                )
            }
            is DatabaseListUiState.Databases -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues)
                        .testTag("DatabaseList"),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    items(
                        items = uiState.items,
                        key = { it.id },
                    ) { database ->
                        DatabaseCard(
                            database = database,
                            onTap = { onOpenDatabase(database) },
                            onEdit = { onEditDatabase(database) },
                            onDelete = { onDeleteDatabase(database.id) },
                            onShowQrCode = onShowQrCode,
                            modifier = Modifier.padding(vertical = 6.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TabletDatabaseListLayout(
    uiState: DatabaseListUiState,
    onAddDatabase: () -> Unit,
    onEditDatabase: (DittoDatabase) -> Unit,
    onOpenDatabase: (DittoDatabase) -> Unit,
    onDeleteDatabase: (Long) -> Unit,
    onShowQrCode: (DittoDatabase) -> Unit,
    onScanQrCode: () -> Unit,
) {
    val context = LocalContext.current

    Box(modifier = Modifier.fillMaxSize()) {
        DotGridBackground()

        // Left panel
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .width(320.dp)
                .padding(start = 32.dp, top = 32.dp, end = 32.dp)
                .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Bottom)),
        ) {
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "Edge Studio",
                style = MaterialTheme.typography.headlineLarge,
                color = SulfurYellow,
            )
            Spacer(modifier = Modifier.height(24.dp))
            Button(
                onClick = onAddDatabase,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = SulfurYellow,
                    contentColor = JetBlack,
                ),
            ) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Database Config")
            }
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedButton(
                onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://portal.ditto.live/"))
                    context.startActivity(intent)
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Outlined.Cloud, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Ditto Portal")
            }
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedButton(
                onClick = onScanQrCode,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Outlined.QrCodeScanner, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Import QR Code")
            }
        }

        // Right panel — database grid
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .padding(start = 320.dp),
        ) {
            when (uiState) {
                is DatabaseListUiState.Loading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                is DatabaseListUiState.Empty -> {
                    EmptyDatabasesView()
                }
                is DatabaseListUiState.Databases -> {
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = 350.dp),
                        modifier = Modifier
                            .fillMaxSize()
                            .testTag("DatabaseList"),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(
                            items = uiState.items,
                            key = { it.id },
                        ) { database ->
                            DatabaseCard(
                                database = database,
                                onTap = { onOpenDatabase(database) },
                                onEdit = { onEditDatabase(database) },
                                onDelete = { onDeleteDatabase(database.id) },
                                onShowQrCode = onShowQrCode,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DotGridBackground(modifier: Modifier = Modifier) {
    val dotColor = Color(0xFF282624)
    Canvas(modifier = modifier.fillMaxSize()) {
        val spacing = 24.dp.toPx()
        val half = 4.dp.toPx()
        val cols = (size.width / spacing).toInt() + 2
        val rows = (size.height / spacing).toInt() + 2
        val path = Path()
        for (row in 0..rows) {
            for (col in 0..cols) {
                val cx = col * spacing
                val cy = row * spacing
                path.reset()
                path.moveTo(cx, cy - half)
                path.lineTo(cx + half, cy)
                path.lineTo(cx, cy + half)
                path.lineTo(cx - half, cy)
                path.close()
                drawPath(path, color = dotColor)
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun DatabaseListScreenEmptyPreview() {
    EdgeStudioTheme {
        PhoneDatabaseListLayout(
            uiState = DatabaseListUiState.Empty,
            onAddDatabase = {},
            onEditDatabase = {},
            onOpenDatabase = {},
            onDeleteDatabase = {},
            onShowQrCode = {},
            onScanQrCode = {},
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun DatabaseListScreenWithItemsPreview() {
    EdgeStudioTheme {
        PhoneDatabaseListLayout(
            uiState = DatabaseListUiState.Databases(
                listOf(
                    DittoDatabase(id = 1, name = "Production", databaseId = "abc123", token = "tok_xyz"),
                    DittoDatabase(id = 2, name = "Staging", databaseId = "def456", token = "tok_abc"),
                ),
            ),
            onAddDatabase = {},
            onEditDatabase = {},
            onOpenDatabase = {},
            onDeleteDatabase = {},
            onShowQrCode = {},
            onScanQrCode = {},
        )
    }
}
