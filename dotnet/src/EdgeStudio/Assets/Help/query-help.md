# Query

Execute DQL queries against the local Ditto store.

## Basic Syntax

```sql
-- Select all documents from a collection
SELECT * FROM collection_name

-- Select with filter
SELECT * FROM cars WHERE make = 'Toyota'

-- Insert a document
INSERT INTO cars DOCUMENTS ({ '_id': 'car1', 'make': 'Toyota', 'model': 'Camry' })

-- Update documents
UPDATE cars SET mileage = 50000 WHERE _id = 'car1'

-- Delete documents
DELETE FROM cars WHERE _id = 'car1'
```

## Keyboard Shortcuts

- **Ctrl+Enter** — Execute query
- **Ctrl+/** — Toggle comment

## Tips

- Use the **History** tab to re-run previous queries
- Save frequently-used queries to **Favorites**
- Use **Explain** tab to inspect the query plan
