# Query Workbench

The **Query Workbench** is where you author, execute, and iterate on DQL queries against the local Ditto store. It surfaces collection structure, query history, saved favourites, and the result set in one place.

## Collections 
Ditto stores documents in [collections](https://docs.ditto.live/key-concepts/apps-and-collections#collections).  Documents are synced into collections using [Subscriptions](https://docs.ditto.live/key-concepts/syncing-data).  No collections will appear until you either [INSERT](https://docs.ditto.live/dql/insert) a document into a collection OR you sync a collection from other peers. 

## Query Help

### Writing DQL Queries

Edge Studio uses **Ditto Query Language (DQL)**, a SQL-like language for reading and writing data in a Ditto database.

#### Basic [SELECT](https://docs.ditto.live/dql/select)

```sql
SELECT * FROM tasks 
SELECT _id, title FROM tasks WHERE done = false 
```

#### Filtering

```sql
SELECT * FROM tasks WHERE deleted = false
SELECT * FROM users WHERE age > 21 AND active = true
```

#### Mutations

- [Insert](https://docs.ditto.live/dql/insert) a document

```sql
INSERT INTO tasks DOCUMENTS ({ '_id': 'task1-1', 'title': 'Test Titlet', 'done': false, 'deleted': false })
```

- [Update](https://docs.ditto.live/dql/update) documents

```sql
UPDATE tasks SET done = true WHERE _id = 'task1-1'
```

- [Evict](https://docs.ditto.live/dql/evict) documents

```sql
EVICT FROM tasks WHERE _id = 'task1-1'
```

- For **delete** - please [read the documentation](https://docs.ditto.live/dql/delete) before running a delete statement.

---

## Execution Modes

| Mode | Description |
|------|-------------|
| **Local** | Executes against the local Ditto store on this device |
| **HTTP** | Executes via the Ditto HTTP API (requires HTTP API URL and key configured) |

## Query Results

### Raw Mode

### Table Mode

### Profile Mode

The third tab next to **Raw** and **Table** shows an execution-plan profile for the last `SELECT` you ran. Profile capture requires **Collect Metrics** to be enabled in Settings — on macOS / iPadOS open Settings (⌘,) and toggle it on; on Android open **Database List → gear icon → Settings** — then re-run your query.

- **Card view** — every operator in the plan with its stats badges and attributes. Recursively nests child operators inside their parent.
- **Plan view** — top-down tree of operator boxes connected by T-junction lines. Each box shows the operator's `exec` time (its own non-overlapping CPU work) and a percent badge — the operator's **% of operator execution time**, i.e. its share of the plan's total CPU work. Badges across all visible boxes sum to 100%; an operator's box turns **orange** when its share exceeds 50% (the plan bottleneck). Same idiom as SQL Server's "% of total plan cost" and Snowflake's "% of overall compute time".
- **Badges (Card view)**: `in` / `out` = document counts in/out, `exec` = CPU time inside the operator, `recv` = time waiting on upstream operators, `send` = time pushing output downstream.

Profiles only fire for `SELECT` statements via the Local execute mode — `INSERT` / `UPDATE` / `DELETE` / `EVICT` and HTTP-mode queries don't capture one. On macOS / iPadOS, see the **User Guide → Collections & Query → Execution Profile** section for the full reference (the User Guide is not shipped on Android).

### Row Actions (right-click / long-press)

On macOS / iPadOS, **right-click** any document row in **Raw** or **Table** mode; on Android, **long-press** the row — either gesture opens a per-row action menu:

- **Copy JSON** — full document to clipboard.
- **Copy _id** — just the document's `_id` value. *(macOS / iPadOS only — Android's row menu offers Copy JSON, Add Attachment…, and Delete Attachment….)*
- **Add Attachment…** — pick a file from disk, enter a field name, upload to Ditto. The attachment token is written back to the document.
- **Delete Attachment…** — open a sheet listing every detected attachment field on the document with toggles. Selected fields are nulled via `UPDATE <collection> SET <field> = null WHERE _id = '<docId>'`.

On macOS / iPadOS, see **User Guide → Collections & Query → Attachments** for the full attachment workflow including viewing and opening files from the Document Viewer (the User Guide is not shipped on Android).

### Pagination

---

# Inspector

## History & Favorites

- Queries are automatically saved to **History** after each successful execution.
- Tap a history or favorites entry in the inspector to load it into the editor.
- Right-click a history entry (macOS / iPadOS) or long-press it (Android) to add it to Favorites or delete it.

## JSON Viewer

When you select a JSON document in the RAW or Table view a copy of that document is put in the clip board and the JSON Viewer is loaded so you can see the information better.  

---

## Indexes

Indexes improve query performance on frequently-filtered fields. Available in Ditto SDK v4.12+.

### View Existing Indexes

```sql
SELECT * FROM system:indexes
```

### Create an Index

```sql
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks (status)

-- Composite index: multiple fields, optional ASC/DESC per field
CREATE INDEX IF NOT EXISTS idx_tasks_status_createdAt ON tasks (status ASC, createdAt DESC)
```

- Index names must be unique per collection.
- Indexes can span **multiple fields** (composite). Field order matters: put equality-filtered fields first, then range or sort fields.
- Use `IF NOT EXISTS` to avoid errors on re-creation.

### Drop an Index

```sql
DROP INDEX IF EXISTS idx_tasks_status ON tasks
```

### Multi-Index Query Optimization

DQL v4.13+ supports **union and intersect scans**, allowing the optimizer to use multiple indexes in a single query:

```sql
-- Uses separate indexes on status and priority via union scan
SELECT * FROM tasks WHERE status = 'active' OR priority = 'high'
```

### Restrictions

- **Sub-field indexing** — `WHERE a.b = 1` requires an explicit index on `(a.b)`.
- **Functional predicates** like `LOWER(field)` or `ILIKE` cannot use indexes.
- `registerSubscription` does not support indexed queries.
- The HTTP API does not support custom indexes.
- Only the latest data-type variant of a field is indexed.
