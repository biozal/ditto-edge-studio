# Observers

Observers watch for changes in the local Ditto store and emit events in real time.

## Overview

An observer fires whenever documents matching its query are inserted, updated, or deleted locally.

## Adding an Observer

1. Click **+** in the listing panel
2. Enter a DQL query to watch
3. Click **Observe**

## Event Types

- **INSERT** — A new document matched the query
- **UPDATE** — A matching document was changed
- **DELETE** — A matching document was removed

## Tips

- Observers are local — they do not affect sync
- Use narrow queries to reduce event noise
- Events stream in real time as data changes
