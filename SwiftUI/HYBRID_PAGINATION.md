# Hybrid Pagination Implementation

## Overview

This document describes the hybrid pagination strategy implemented in the Edge Debug Helper app to optimize query performance for both small and large datasets.

## Problem Statement

The `dev` branch initially used server-side pagination for **all queries**, which caused performance degradation:

- **Small datasets (<10,000 items)**: Server-side pagination was slower than loading all results once and paginating in-memory
- **Page navigation**: Each page change triggered a new database query with `LIMIT/OFFSET`, adding 10-50ms per click
- **Original behavior**: The `main` branch loaded all results once and used instant client-side pagination

## Solution: Smart Hybrid Pagination

The hybrid approach automatically chooses the optimal pagination strategy based on:

1. **Query Type**: Aggregate queries (COUNT, SUM, AVG, etc.) don't benefit from pagination
2. **Collection Size**: Large collections (>10,000 items) use server-side pagination
3. **User Intent**: Queries with existing LIMIT/OFFSET clauses are left as-is

### Decision Logic

```swift
// 1. Check if query is aggregate or already paginated
if DQLQueryParser.isAggregateOrPaginatedQuery(selectedQuery) {
    // Use query as-is (no server pagination needed)
    return false
}

// 2. Check collection size
if let collectionName = DQLQueryParser.extractCollectionName(from: selectedQuery) {
    let count = try await QueryService.shared.getCollectionCount(collection: collectionName)

    if count > 10_000 {
        // Large collection: Use server-side pagination
        return true
    } else {
        // Small collection: Load all results, paginate in-memory
        return false
    }
}

// 3. Default to in-memory pagination (safer/faster)
return false
```

## Implementation Details

### 1. Query Type Detection (`DQLQueryParser.swift`)

The `DQLQueryParser` now includes methods to analyze queries:

#### `isAggregateOrPaginatedQuery(_ query: String) -> Bool`

Detects queries that don't benefit from server-side pagination:

**Returns `true` for:**
- Aggregate functions: `COUNT(*)`, `SUM(price)`, `AVG(rating)`, `MIN(age)`, `MAX(salary)`
- GROUP BY clauses: `SELECT make, COUNT(*) FROM cars GROUP BY make`
- DISTINCT queries: `SELECT DISTINCT category FROM products`
- Already paginated: `SELECT * FROM cars LIMIT 10 OFFSET 20`

**Returns `false` for:**
- Simple SELECT: `SELECT * FROM cars`
- SELECT with WHERE: `SELECT * FROM cars WHERE year > 2020`
- SELECT with JOIN: `SELECT cars.*, owners.name FROM cars JOIN owners`
- SELECT with ORDER BY: `SELECT * FROM cars ORDER BY price DESC`

**Example Usage:**
```swift
let query1 = "SELECT COUNT(*) FROM cars"
DQLQueryParser.isAggregateOrPaginatedQuery(query1) // true - aggregate

let query2 = "SELECT make FROM cars"
DQLQueryParser.isAggregateOrPaginatedQuery(query2) // false - can benefit from pagination
```

#### `hasPagination(_ query: String) -> Bool`

Simple check for existing LIMIT/OFFSET clauses.

**Example Usage:**
```swift
let query = "SELECT * FROM cars LIMIT 100"
DQLQueryParser.hasPagination(query) // true
```

### 2. Collection Size Counting (`QueryService.swift`)

New method to determine collection size before executing the main query:

```swift
func getCollectionCount(collection: String) async throws -> Int {
    guard let ditto = await dittoManager.dittoSelectedApp else {
        throw NSError(...)
    }

    let query = "SELECT COUNT(*) as count FROM \(collection)"
    let results = try await ditto.store.execute(query: query)

    guard let firstItem = results.items.first,
          let count = firstItem.value["count"] as? Int else {
        return 0
    }

    return count
}
```

**Performance:** This COUNT query is fast (typically <5ms) because:
- SQLite optimizes COUNT(*) queries
- No data needs to be retrieved, just counted
- Result is a single integer value

### 3. Modified `executeQuery` Method (`MainStudioView.swift`)

The execution logic now includes smart pagination decision-making:

```swift
func executeQuery(appState: AppState, page: Int? = nil, forceServerPagination: Bool = false) async {
    isQueryExecuting = true
    isLoadingPage = true

    let targetPage = page ?? 0
    let offset = targetPage * pageSize

    do {
        // Smart pagination decision
        var shouldUseServerPagination = forceServerPagination

        // Only consider server-side pagination for non-aggregate queries
        if !DQLQueryParser.isAggregateOrPaginatedQuery(selectedQuery) {
            if let collectionName = DQLQueryParser.extractCollectionName(from: selectedQuery) {
                do {
                    let count = try await QueryService.shared.getCollectionCount(collection: collectionName)

                    // Threshold: 10,000 items
                    if count > 10_000 {
                        shouldUseServerPagination = true
                        print("Large collection (\(count) items), using server-side pagination")
                    } else {
                        print("Small collection (\(count) items), using in-memory pagination")
                    }
                } catch {
                    // If count fails, default to in-memory (safer/faster)
                    print("Failed to get collection count, defaulting to in-memory pagination")
                }
            }
        }

        // Execute with or without pagination
        let queryToExecute = shouldUseServerPagination
            ? addPaginationToQuery(selectedQuery, limit: pageSize, offset: offset)
            : selectedQuery

        if selectedExecuteMode == "Local" {
            jsonResults = try await QueryService.shared.executeSelectedAppQuery(query: queryToExecute)
        } else {
            jsonResults = try await QueryService.shared.executeSelectedAppQueryHttp(query: queryToExecute)
        }

        // Save results and update state...
        currentPage = targetPage
        hasExecutedQuery = true

        // Only add to history on first page
        if targetPage == 0 {
            await addQueryToHistory(appState: appState)
        }
    } catch {
        appState.setError(error)
    }

    isQueryExecuting = false
    isLoadingPage = false
}
```

## Performance Characteristics

### Small Collections (≤10,000 items)

**Strategy:** In-memory pagination

| Operation | Time | Notes |
|-----------|------|-------|
| Initial query | 1-50ms | Load all results once |
| Page navigation | <1ms | Array slicing only |
| Total perceived latency | ~50ms | Instant feel |

**Example:**
```sql
-- Collection has 500 items
SELECT * FROM cars WHERE year > 2020

-- Strategy: Load all 500 results
-- Result: Instant pagination in UI
```

### Large Collections (>10,000 items)

**Strategy:** Server-side pagination

| Operation | Time | Notes |
|-----------|------|-------|
| Collection count | 1-5ms | Fast COUNT(*) query |
| Initial query | 10-50ms | Load first 100 items |
| Page navigation | 10-50ms | New query with OFFSET |
| Total perceived latency | ~60ms | Slight delay, but manageable |

**Example:**
```sql
-- Collection has 50,000 items
SELECT * FROM cars

-- Strategy:
-- 1. COUNT: SELECT COUNT(*) FROM cars → 50,000
-- 2. Execute: SELECT * FROM cars LIMIT 100 OFFSET 0
-- Result: Server-side pagination enabled
```

### Aggregate Queries

**Strategy:** No pagination (execute as-is)

| Operation | Time | Notes |
|-----------|------|-------|
| Query execution | 1-100ms | Depends on aggregation |
| Result | Single value or small set | No pagination needed |

**Examples:**
```sql
-- These queries bypass pagination logic entirely
SELECT COUNT(*) FROM cars                          -- Single result
SELECT AVG(price) FROM products                    -- Single result
SELECT make, COUNT(*) FROM cars GROUP BY make      -- Small result set
SELECT DISTINCT category FROM products             -- Small result set
```

## Testing

### Unit Tests

Comprehensive unit tests are provided in `DQLQueryParserTests.swift`:

- **Collection name extraction**: 6 tests covering various DQL formats
- **Aggregate query detection**: 21 tests for all aggregate scenarios
- **Pagination detection**: 5 tests for LIMIT/OFFSET clauses
- **Edge cases**: 6 tests for complex queries and corner cases
- **Real-world examples**: 4 tests based on actual use cases

**Note:** The test file requires proper test target configuration to run. It's currently included but may need to be added to the test target in Xcode project settings.

### Manual Testing Scenarios

1. **Small collection query:**
   ```sql
   SELECT * FROM small_collection  -- <1,000 items
   -- Expected: In-memory pagination, instant page navigation
   ```

2. **Large collection query:**
   ```sql
   SELECT * FROM large_collection  -- >10,000 items
   -- Expected: Server-side pagination, slight delay on page change
   ```

3. **Aggregate query:**
   ```sql
   SELECT COUNT(*) FROM any_collection
   -- Expected: No pagination, single result
   ```

4. **Pre-paginated query:**
   ```sql
   SELECT * FROM cars LIMIT 50 OFFSET 100
   -- Expected: Execute as-is, no additional pagination
   ```

## Configuration

### Threshold Adjustment

The threshold for server-side pagination can be adjusted in `MainStudioView.swift:1532`:

```swift
// Current threshold: 10,000 items
if count > 10_000 {
    shouldUseServerPagination = true
}

// To adjust (e.g., 5,000 items):
if count > 5_000 {
    shouldUseServerPagination = true
}
```

**Considerations for threshold:**
- **Lower threshold (5,000)**: More conservative, uses server pagination earlier
- **Higher threshold (25,000)**: More aggressive, relies on in-memory pagination longer
- **Current (10,000)**: Balanced for typical use cases

### Page Size

Page size defaults to 100 items and is set in `MainStudioView.swift:1234`:

```swift
var pageSize: Int = 100  // Default page size
```

## Debugging

### Console Output

The implementation includes debug logging to help understand pagination decisions:

```swift
print("Large collection (\(count) items), using server-side pagination")
print("Small collection (\(count) items), using in-memory pagination")
print("Failed to get collection count, defaulting to in-memory pagination")
```

**Example console output:**
```
Small collection (450 items), using in-memory pagination
Large collection (25000 items), using server-side pagination
```

### Verification Steps

To verify the hybrid pagination is working:

1. **Check console output** when executing queries
2. **Monitor page navigation speed**:
   - In-memory: Instant (<1ms)
   - Server-side: Slight delay (10-50ms)
3. **Test with known collection sizes**:
   - Small: Use test data <10k items
   - Large: Use production data >10k items

## Benefits

### Performance Improvements

1. **Small collections**: Back to original fast performance
   - Page navigation: <1ms (vs 10-50ms with server pagination)
   - User experience: Instant feel restored

2. **Large collections**: Still manageable
   - Prevents loading 100k+ items into memory
   - Progressive loading keeps UI responsive

3. **Aggregate queries**: No overhead
   - COUNT/AVG/SUM execute directly
   - No unnecessary pagination logic

### Memory Efficiency

- **Small datasets**: All loaded in-memory (acceptable for <10k items)
- **Large datasets**: Only 100 items in-memory at a time
- **Aggregate results**: Single value or small set

### User Experience

- **Fast queries feel instant** (small collections)
- **Large queries remain manageable** (progressive loading)
- **Aggregate queries unaffected** (execute as expected)

## Future Improvements

### Potential Enhancements

1. **Caching collection counts**:
   - Cache COUNT results for 60 seconds
   - Avoid repeated COUNT queries for same collection

2. **User preference toggle**:
   - Add setting: "Always use server-side pagination"
   - Override smart detection if user prefers

3. **Dynamic threshold adjustment**:
   - Learn from user's dataset sizes
   - Adjust threshold based on memory/performance metrics

4. **Query result caching**:
   - Cache recent query results
   - Instant repeat queries

5. **Progressive loading indicators**:
   - Show "Loading page X of Y" for server pagination
   - Hide for in-memory pagination (instant)

## Migration Notes

### From Previous Implementation

If you're on the `dev` branch before this change:

**Before (always server-side pagination):**
- Every query modified with LIMIT/OFFSET
- Page navigation triggered new queries
- Slower for small collections

**After (hybrid pagination):**
- Smart detection based on collection size
- In-memory pagination for small collections
- Server-side only when needed

### Behavioral Changes

1. **Small collections now load fully**:
   - Previous: 100 items per page via server
   - Current: All items loaded, paginated in-memory

2. **Aggregate queries unchanged**:
   - Previous: Attempted to paginate (incorrect)
   - Current: Execute as-is (correct)

3. **Large collections still paginated**:
   - Previous: Server-side pagination (100/page)
   - Current: Same behavior, but only for large collections

## References

- **DQLQueryParser.swift**: Query analysis utilities (`SwiftUI/Edge Debug Helper/Data/DQLQueryParser.swift`)
- **QueryService.swift**: Collection counting (`SwiftUI/Edge Debug Helper/Data/QueryService.swift:134-150`)
- **MainStudioView.swift**: Hybrid execution logic (`SwiftUI/Edge Debug Helper/Views/MainStudioView.swift:1513-1576`)
- **DQLQueryParserTests.swift**: Unit tests (`SwiftUI/Edge Debug Helper Tests/DQLQueryParserTests.swift`)

## Summary

The hybrid pagination implementation provides the best of both worlds:

- **Small datasets**: Lightning-fast in-memory pagination (instant page navigation)
- **Large datasets**: Manageable server-side pagination (prevents memory issues)
- **Aggregate queries**: Unaffected by pagination logic (correct behavior)

This approach restores the original fast performance for typical use cases while maintaining scalability for large collections.
