package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.NetworkInterfaceInfo
import com.costoda.dittoedgestudio.domain.model.P2PTransportInfo
import com.costoda.dittoedgestudio.viewmodel.PeersUiState

@Composable
fun ConnectedPeersScreen(
    peersUiState: PeersUiState,
    networkInterfaces: List<NetworkInterfaceInfo>,
    p2pTransports: List<P2PTransportInfo>,
    onLoadDiagnostics: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LaunchedEffect(Unit) { onLoadDiagnostics() }

    when (val state = peersUiState) {
        PeersUiState.Initializing -> {
            Box(
                modifier = modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
        }
        is PeersUiState.Active -> {
            val gridState = rememberLazyGridState()
            val prevCount = remember { mutableIntStateOf(state.remotePeers.size) }

            LaunchedEffect(state.remotePeers.size) {
                if (state.remotePeers.size > prevCount.intValue) {
                    gridState.animateScrollToItem(0)
                }
                prevCount.intValue = state.remotePeers.size
            }

            LazyVerticalGrid(
                state = gridState,
                columns = GridCells.Adaptive(minSize = 300.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = modifier.fillMaxSize(),
            ) {
                // Remote peers (0..N)
                items(state.remotePeers, key = { it.peerId }) { peer ->
                    RemotePeerCard(peer)
                }

                // Local peer (always last in the peers grid section)
                state.localPeer?.let { local ->
                    item(key = "local_peer") {
                        LocalPeerCard(local)
                    }
                }

                // "Local Network" section header
                if (networkInterfaces.isNotEmpty() || p2pTransports.isNotEmpty()) {
                    item(
                        key = "net_divider",
                        span = { GridItemSpan(maxLineSpan) },
                    ) {
                        SectionDivider(title = "Local Network")
                    }
                }

                // Network interface cards (WiFi, Ethernet)
                items(networkInterfaces, key = { it.id }) { iface ->
                    NetworkInterfaceCard(iface)
                }

                // P2P transport status cards (WiFi Aware, WiFi Direct)
                items(p2pTransports, key = { it.kind.name }) { transport ->
                    P2PTransportCard(transport)
                }
            }
        }
    }
}

@Composable
private fun SectionDivider(title: String) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        HorizontalDivider(modifier = Modifier.weight(1f))
        Text(
            text = title,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        HorizontalDivider(modifier = Modifier.weight(1f))
    }
}
