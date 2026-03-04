# Observable Help

## How Observers Work

An **Observer** registers a live DQL query against the local Ditto store. Whenever documents matching the query are inserted, updated, or deleted — whether by a local write or a sync from a remote peer — the observer fires an event.

Observers are useful for:
- Watching a specific collection for real-time changes
- Debugging sync behaviour by seeing exactly when and how documents arrive
- Verifying that subscriptions are delivering the expected data

---

## Adding an Observer

1. Tap the **+** button in the sidebar bottom bar and choose *Add Observer*.
2. Enter a descriptive name and a valid DQL `SELECT` query.
3. Tap **Save**.

The observer appears in the list in an *inactive* state (no events collected yet).

---

## Activating an Observer

Tap the **play** button next to an observer row to activate it. Once active, Edge Studio registers a live store observer with Ditto. Events will appear in the event list on the right as documents change.

Tap the **stop** button to deactivate the observer and stop collecting events.

---

## Reading Events

Each event row shows:
- **Timestamp** — when the event fired
- **Diff summary** — how many documents were inserted, updated, deleted, or moved

Select an event to view the full document snapshot and diff details in the detail panel.

---

## Best Practices

- Use specific `WHERE` clauses to limit observer noise on large collections.
- Deactivate observers when not in use — active observers consume resources.
- Use observers in combination with subscriptions: subscribe first so documents sync, then observe to verify they arrived correctly.
