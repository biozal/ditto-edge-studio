# Subscription and Sync Help

## Subscriptions

Subscriptions tell Ditto which documents to sync from other peers. A subscription is a DQL `SELECT` query — any document matching the query will be replicated to your device when a peer that has it comes online.  Full information about subscriptions can be found in the Ditto [documentation](https://docs.ditto.live/key-concepts/syncing-data#subscription-queries). Subscriptions do not support projections, so most of the time the syntax is as simple as:

```sql
SELECT * FROM collection-name
```

It's always recommended to have a good sync strategy add and a [WHERE](https://docs.ditto.live/dql/select#where) clause to limit the amount of data you are syncing.

**Adding a subscription:**
Tap the **+** button in the bottom-left of the sidebar, then choose *Add Subscription*. Enter a name, a valid DQL query, and optional query arguments.

**Removing a subscription:**
Swipe left on the subscription row (iPadOS) or right-click and choose *Delete* (macOS).

**Best practices:**
- Keep subscription queries as specific as possible to minimize data transfer.

---

## Peers List

The **Peers List** tab shows all devices currently connected to this Ditto database. Each row displays:

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

## Presence Viewer

The **Presence Viewer** tab renders a live graph of the peer mesh. Nodes represent devices; edges represent active connections. This is useful for visualising network topology and diagnosing connectivity issues.  This is a visual representation of what's in the Peer List.  

## Updating Transports
The **Cog** icon in the upper right handle corner of the Details part of the screen can be used to turn on and off transports like Bluetooth, P2P WiFi (AWDL), and LAN traffic.  This can allow you to test fail over and firewall settings to validate that your app can talk to other devices on the network without adding a bunch of debug code into your app.


