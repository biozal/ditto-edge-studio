# Query Editor

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

### Pagination

---

# Inspector

## History & Favorites

- Queries are automatically saved to **History** after each successful execution.
- Tap a history or favorites entry in the inspector to load it into the editor.
- Right-click a history entry to add it to Favorites or delete it.

## JSON Viewer

When you select a JSON document in the RAW or Table view a copy of that document is put in the clip board and the JSON Viewer is loaded so you can see the information better.  
