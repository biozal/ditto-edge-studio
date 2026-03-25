# Subscriptions

Subscriptions define which data Ditto syncs to this device.

## Overview

A subscription tells Ditto which documents from which collections to sync.
Without a subscription, no data flows to or from this peer.

## Adding a Subscription

1. Click **+** in the listing panel
2. Enter a DQL query (e.g. `SELECT * FROM cars`)
3. Click **Subscribe**

## DQL Examples

```sql
-- Subscribe to all cars
SELECT * FROM cars

-- Subscribe to cars where mileage < 100000
SELECT * FROM cars WHERE mileage < 100000
```

## Tips

- Keep subscriptions as narrow as possible to reduce sync load
- Use `WHERE` clauses to filter what gets synced
- Multiple subscriptions can be active at once
