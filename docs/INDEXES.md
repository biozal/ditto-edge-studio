# DQL Index Reference

Comprehensive reference for creating and managing indexes in Ditto databases using DQL.

**Minimum SDK version:** Ditto v4.12+

---

## Overview

Indexes improve query performance by allowing the Ditto query optimizer to locate matching documents without scanning every document in a collection. They are especially beneficial for:

- Collections with large document counts
- Queries that filter on a specific field frequently (e.g. `WHERE status = 'active'`)
- Real-time observer queries that re-evaluate on every change

---

## Viewing Indexes

List all indexes across all collections:

```sql
SELECT * FROM system:indexes
```

Each result row contains:

| Field | Description |
|-------|-------------|
| `_id` | Index name |
| `collection` | Collection the index belongs to |
| `fields` | Array of indexed field names |

Example result:

```json
{
  "_id": "idx_tasks_status",
  "collection": "tasks",
  "fields": ["status"]
}
```

---

## Creating Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks (status)
```

**Syntax breakdown:**

```sql
CREATE INDEX [IF NOT EXISTS] <index_name> ON <collection> (<field>)
```

- `IF NOT EXISTS` — prevents an error if the index already exists (recommended)
- `<index_name>` — must be unique within the collection; use a descriptive convention like `idx_{collection}_{field}`
- `<field>` — the single field to index; use dot notation for sub-fields (e.g. `metadata.priority`)

### Examples

```sql
-- Index on a top-level field
CREATE INDEX IF NOT EXISTS idx_tasks_done ON tasks (done)

-- Index on a nested sub-field
CREATE INDEX IF NOT EXISTS idx_tasks_meta_priority ON tasks (metadata.priority)

-- Multiple indexes on the same collection
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email)
CREATE INDEX IF NOT EXISTS idx_users_role ON users (role)
```

---

## Dropping Indexes

```sql
DROP INDEX IF EXISTS idx_tasks_status ON tasks
```

**Syntax:**

```sql
DROP INDEX [IF EXISTS] <index_name> ON <collection>
```

- `IF EXISTS` — prevents an error if the index does not exist

---

## Forcing Index Usage

Use `USE INDEX` to hint the optimizer to use a specific index:

```sql
SELECT * FROM tasks USE INDEX (idx_tasks_status) WHERE status = 'active'
```

Use `USE DIRECTIVES` for more advanced query planning control (see Ditto documentation).

---

## Query Optimization

### How the Optimizer Uses Indexes

The query optimizer uses an index when a query's `WHERE` clause filters on the indexed field using an equality or range predicate:

```sql
-- Uses idx_tasks_status
SELECT * FROM tasks WHERE status = 'active'

-- Uses idx_tasks_done
SELECT * FROM tasks WHERE done = false
```

### Selectivity

Indexes are most effective on **high-selectivity** fields — fields with many distinct values. A field like `status` with only 2–3 values may yield less benefit than a field like `userId` with thousands of distinct values.

### Union and Intersect Scans (v4.13+)

Ditto v4.13+ supports **union scans** (for `OR`/`IN`) and **intersect scans** (for `AND`), allowing the optimizer to use multiple indexes simultaneously:

```sql
-- Union scan: uses separate indexes on status and priority
SELECT * FROM tasks WHERE status = 'active' OR priority = 'high'

-- Intersect scan: uses separate indexes on status and done
SELECT * FROM tasks WHERE status = 'active' AND done = false

-- IN operator (union scan)
SELECT * FROM tasks WHERE status IN ('active', 'pending')
```

---

## API Support Matrix

| API | Supports Custom Indexes |
|-----|------------------------|
| `ditto.store.execute()` | ✅ Yes |
| `ditto.store.registerObserver()` | ✅ Yes |
| `ditto.store.registerSubscription()` | ❌ No |
| HTTP API | ❌ No |

---

## Restrictions

| Restriction | Detail |
|-------------|--------|
| **Single field only** | Composite (multi-field) indexes are not supported |
| **Latest type variant only** | Only the most recent data-type of a field is indexed |
| **Sub-field dot notation** | `WHERE a.b = 1` requires an explicit index on `(a.b)` |
| **Functional predicates** | `LOWER(field)`, `ILIKE`, etc. cannot use indexes |
| **registerSubscription** | Does not support index queries |
| **HTTP API** | Does not support custom indexes |
| **OR/IN/≠ (v4.12)** | Not supported in v4.12; supported via union scans in v4.13+ |

---

## Edge Studio Integration

Edge Studio surfaces indexes directly in the sidebar:

- **Collections tree view** — each collection expands to show its indexes; each index expands to show its fields
- **Add Index sheet** — FAB → "Add Index" to create a new index on any collection
- **Refresh** — click the refresh button in the collections header to re-fetch indexes after changes
- **Query editor** — run `SELECT * FROM system:indexes` directly in the query editor

---

## Further Reading

- [Ditto DQL Indexing Documentation](https://docs.ditto.live/dql/indexing)
- [DQL SELECT Reference](https://docs.ditto.live/dql/select)
- [DQL Restrictions](https://docs.ditto.live/dql/indexing#restrictions)
