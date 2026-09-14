# Presence

The **Presence** section combines two related debug surfaces: the live list of peers your device is currently exchanging data with, and a visual graph of the mesh topology. Subscriptions — which control *what* documents your device syncs — are managed here too because they directly drive what shows up in the peer list once sync runs.

---

## Subscriptions

Subscriptions tell Ditto which documents to sync from other peers. A subscription is a DQL `SELECT` query — any document matching the query will be replicated to your device when a peer that has it comes online.  Full information about subscriptions can be found in the Ditto [documentation](https://docs.ditto.live/key-concepts/syncing-data#subscription-queries). Subscriptions do not support projections, so most of the time the syntax is as simple as:

```sql
SELECT * FROM collection-name
```

It's always recommended to have a good sync strategy add and a [WHERE](https://docs.ditto.live/dql/select#where) clause to limit the amount of data you are syncing.

**Adding a subscription:**
On macOS / iPadOS, tap the **+** button in the bottom-left of the sidebar, then choose *Add Subscription*. On Android, tap the **+** floating action button (FAB) in the Subscriptions list. Enter a name, a valid DQL query, and optional query arguments.

**Removing a subscription:**
Swipe left on the subscription row (iPadOS) or right-click and choose *Delete* (macOS). On Android, tap the delete (trash) icon on the subscription row.

**Bulk sharing via QR:**
The QR icon at the top of the Subscriptions list encodes **all** subscriptions into a single QR code that any Edge Studio instance (macOS, iPadOS, or Android) can scan to import them at once (`EDS_SUBS1:` payload).

**Bulk import:**
The download icon at the top of the Subscriptions list offers two paths:
- **From QR code** — scans a subscription QR code produced by another Edge Studio instance and imports every subscription in it.
- **From server** *(requires the database's HTTP API URL + key)* — queries the server-side `__small_peer_info` for every peer's `local_subscriptions`, filters out system collections and subscriptions you already have, and lets you cherry-pick with checkboxes.

**Best practices:**
- Keep subscription queries as specific as possible to minimize data transfer.

---

## Peers

The **Peers** tab shows all devices currently connected to this Ditto database. Each row displays:

| Column | Description |
|--------|-------------|
| Device name | Human-readable identifier for the remote peer |
| Transports | Active transports (WiFi, Bluetooth, WebSocket, etc.) |
| SDK | Language and version of the Ditto SDK running on the peer |

Peers are discovered automatically — no manual configuration required.  This is done by merging data from two different locations:  
- [Presence Graph](https://docs.ditto.live/sdk/latest/sync/using-mesh-presence) 
- [system:data_sync_info](https://docs.ditto.live/sdk/latest/sync/tracking-local-commits#what-are-commit-ids)

## Local Network

The section Local Network gives you informationa about what Local Area Network (LAN) connections Ditto can use on your computer for transport.  

---

## Viewer

The **Viewer** tab renders a live graph of the peer mesh. Nodes represent devices; edges represent active connections. Tap any peer to isolate its neighbourhood — non-incident edges and unrelated peers fade out so you can see exactly who it talks to. The **Direct** toggle limits the graph to peers your device is directly connected to; turn it off to surface the full mesh including peer-to-peer connections that don't involve this device.

Each transport has its own dash pattern in the **Connection Types** legend (Bluetooth as dots, LAN as long bars, P2P WiFi as even dashes, WebSocket as dash-dot, Cloud as dash-circle), so transports can be distinguished by shape — not just colour.

Use the **reset** button (crosshairs icon) to recenter the camera and snap any dragged peers back to their layout positions.

## Updating Transports
The **Cog** icon in the upper right handle corner of the Details part of the screen can be used to turn on and off transports like Bluetooth, P2P WiFi (AWDL), and LAN traffic.  This can allow you to test fail over and firewall settings to validate that your app can talk to other devices on the network without adding a bunch of debug code into your app.


