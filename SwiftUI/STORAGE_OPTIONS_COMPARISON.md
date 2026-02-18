# Storage Options Comparison

This document compares different approaches for storing local cache data in Edge Debug Helper.

## Current Approach: JSON Files + Keychain

### Architecture
```
┌─────────────────────────┐
│   Keychain (Secure)     │  ← Auth tokens, API keys
├─────────────────────────┤
│  JSON Files (Plaintext) │  ← Database configs, history, favorites
│  ~/Library/Application  │
│  Support/ditto_cache/   │
└─────────────────────────┘
```

### Pros ✅
- Simple implementation
- Easy to debug (can read JSON files)
- No external dependencies
- Fast for small datasets
- Portable (can copy files between machines)

### Cons ❌
- **Security:** JSON files unencrypted at rest
- **Performance:** Must load entire file to read/filter
- **Data Integrity:** No ACID guarantees
- **Relationships:** No foreign keys or cascade deletion
- **Concurrency:** Manual locking required
- **Queries:** Must load everything into memory first

### File Structure
```
~/Library/Application Support/ditto_cache/
  ├── database_configs.json          (~5 KB per 10 databases)
  ├── {databaseId}_history.json      (~100 KB per 1000 queries)
  ├── {databaseId}_favorites.json    (~20 KB per 100 favorites)
  ├── {databaseId}_subscriptions.json (~10 KB per 50 subscriptions)
  └── {databaseId}_observables.json  (~15 KB per 50 observables)
```

---

## Option 1: SQLCipher (Encrypted SQLite)

### Architecture
```
┌─────────────────────────────────┐
│   Keychain (Secure)             │  ← Auth tokens, API keys, DB encryption key
├─────────────────────────────────┤
│  SQLCipher (AES-256 Encrypted)  │  ← All cache data encrypted
│  ~/Library/Application Support/ │
│  ditto_cache/ditto_encrypted.db │
└─────────────────────────────────┘
```

### Pros ✅
- **Security:** 256-bit AES encryption at rest
- **Performance:** Indexed queries, no full table scans
- **Data Integrity:** ACID transactions
- **Relationships:** Foreign keys + cascade deletion
- **Concurrency:** SQLite handles locking automatically
- **Queries:** SQL for filtering/sorting
- **Battle-tested:** Used by Signal, WhatsApp, 1Password

### Cons ❌
- **Complexity:** More code than JSON
- **Dependencies:** Requires SQLCipher library
- **Build Setup:** May need build configuration
- **Debugging:** Can't just open file in text editor
- **Migration:** One-time migration from JSON needed

### File Structure
```
~/Library/Application Support/ditto_cache/
  └── ditto_encrypted.db  (~100-500 KB for typical usage)
```

### Implementation Effort
- **Using raw SQLCipher:** ~7-11 days
- **Using GRDB + SQLCipher:** ~5-8 days (type-safe API)

---

## Option 2: GRDB with SQLCipher

### Architecture
```
┌─────────────────────────────────────┐
│   Keychain (Secure)                 │  ← Auth tokens, API keys, DB key
├─────────────────────────────────────┤
│  GRDB (SQLCipher-backed)            │  ← Type-safe Swift layer
│  └─ SQLCipher (AES-256 Encrypted)   │  ← Encrypted storage
│     ~/Library/Application Support/  │
│     ditto_cache/ditto_encrypted.db  │
└─────────────────────────────────────┘
```

### Pros ✅
- **All SQLCipher benefits** (security, performance, integrity)
- **Type-safe:** Swift structs instead of raw SQL
- **Migrations:** Built-in migration support
- **No build config:** Works out of the box
- **Well-maintained:** Active development, used by Day One, Bear
- **Better errors:** Swift error handling
- **Observables:** Database change notifications
- **Modern API:** Async/await, Combine support

### Cons ❌
- **Learning curve:** New API to learn
- **Dependency:** GRDB framework added
- **Binary size:** Larger than raw SQLCipher

### Code Comparison

**Current (JSON):**
```swift
func saveQueryHistory(_ databaseId: String, query: String) async throws {
    var history = try await loadHistory(databaseId)
    history.insert(QueryHistory(query: query), at: 0)
    let data = try JSONEncoder().encode(history)
    try data.write(to: getHistoryFileURL(databaseId))
}
```

**SQLCipher (Raw):**
```swift
func saveQueryHistory(_ databaseId: String, query: String) async throws {
    let sql = "INSERT INTO history (_id, databaseId, query, createdDate) VALUES (?, ?, ?, ?)"
    var statement: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    sqlite3_bind_text(statement, 1, UUID().uuidString, -1, nil)
    sqlite3_bind_text(statement, 2, databaseId, -1, nil)
    sqlite3_bind_text(statement, 3, query, -1, nil)
    sqlite3_bind_text(statement, 4, ISO8601DateFormatter().string(from: Date()), -1, nil)
    sqlite3_step(statement)
    sqlite3_finalize(statement)
}
```

**GRDB:**
```swift
func saveQueryHistory(_ databaseId: String, query: String) async throws {
    try await dbQueue.write { db in
        var record = QueryHistory(
            databaseId: databaseId,
            query: query,
            createdDate: Date()
        )
        try record.insert(db)
    }
}

struct QueryHistory: Codable, FetchableRecord, PersistableRecord {
    var _id: String = UUID().uuidString
    var databaseId: String
    var query: String
    var createdDate: Date
}
```

### Implementation Effort
- **Setup:** 1-2 hours (add package)
- **Service rewrite:** 1-2 days
- **Repository updates:** 2-3 days
- **Migration:** 1 day
- **Testing:** 2-3 days
- **Total:** ~5-8 days

---

## Option 3: Encrypted JSON Files

### Architecture
```
┌─────────────────────────────┐
│   Keychain (Secure)         │  ← Auth tokens, API keys, file encryption key
├─────────────────────────────┤
│  Encrypted JSON Files       │  ← AES-256 encrypted JSON
│  ~/Library/Application      │
│  Support/ditto_cache/       │
└─────────────────────────────┘
```

### Implementation
Encrypt JSON files using CryptoKit before writing to disk.

### Pros ✅
- **Security:** Files encrypted at rest
- **Simple:** Minimal code changes
- **No dependencies:** Uses Apple's CryptoKit
- **Fast implementation:** 1-2 days

### Cons ❌
- **Performance:** Still need to decrypt + load entire file
- **No ACID:** Same integrity issues as current approach
- **No relationships:** Still no foreign keys
- **Memory:** Must decrypt entire file into memory

### Code Changes
```swift
func saveHistory(_ databaseId: String, history: [QueryHistory]) async throws {
    let data = try JSONEncoder().encode(history)

    // Encrypt with CryptoKit
    let key = try await getEncryptionKey()
    let sealedBox = try AES.GCM.seal(data, using: key)

    // Write encrypted data
    try sealedBox.combined!.write(to: getHistoryFileURL(databaseId))
}

func loadHistory(_ databaseId: String) async throws -> [QueryHistory] {
    let encryptedData = try Data(contentsOf: getHistoryFileURL(databaseId))

    // Decrypt with CryptoKit
    let key = try await getEncryptionKey()
    let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
    let data = try AES.GCM.open(sealedBox, using: key)

    // Decode JSON
    return try JSONDecoder().decode([QueryHistory].self, from: data)
}
```

### Implementation Effort
- **Encryption service:** 4-8 hours
- **Repository updates:** 1 day
- **Testing:** 1 day
- **Total:** ~2-3 days

---

## Option 4: Core Data with Encryption

### Architecture
```
┌─────────────────────────────────┐
│   Keychain (Secure)             │  ← Auth tokens, API keys
├─────────────────────────────────┤
│  Core Data (with encryption)    │  ← Apple's ORM
│  ~/Library/Application Support/ │
│  ditto_cache/Store.sqlite       │
└─────────────────────────────────┘
```

### Pros ✅
- **Apple native:** First-party framework
- **ORM features:** Relationships, migrations, faulting
- **Encryption:** NSPersistentStoreDescription.setOption(NSFileProtectionComplete)
- **iCloud sync:** Can sync via CloudKit
- **SwiftUI integration:** @FetchRequest property wrapper

### Cons ❌
- **Complexity:** Steep learning curve
- **Encryption:** Only file-level protection (not true encryption at rest like SQLCipher)
- **Performance:** Slower than raw SQLite
- **Verbose:** Requires .xcdatamodeld files
- **Migration pain:** Schema changes are difficult

### Implementation Effort
- **Model creation:** 1-2 days
- **Repository updates:** 3-4 days
- **Migration:** 1-2 days
- **Testing:** 2-3 days
- **Total:** ~7-11 days

---

## Comparison Table

| Feature | JSON | SQLCipher | GRDB+SQLCipher | Encrypted JSON | Core Data |
|---------|------|-----------|----------------|----------------|-----------|
| **Security** | ❌ None | ✅ AES-256 | ✅ AES-256 | ✅ AES-256 | ⚠️ File-level |
| **Performance** | ⚠️ Slow (large files) | ✅ Fast (indexed) | ✅ Fast (indexed) | ❌ Slow | ⚠️ Medium |
| **ACID** | ❌ No | ✅ Yes | ✅ Yes | ❌ No | ✅ Yes |
| **Relationships** | ❌ Manual | ✅ Foreign keys | ✅ Foreign keys | ❌ Manual | ✅ Relationships |
| **Type Safety** | ⚠️ Codable | ❌ Raw SQL | ✅ Swift structs | ⚠️ Codable | ✅ NSManagedObject |
| **Implementation** | ✅ 0 days (current) | ⚠️ 7-11 days | ⚠️ 5-8 days | ✅ 2-3 days | ⚠️ 7-11 days |
| **Dependencies** | ✅ None | ⚠️ SQLCipher | ⚠️ GRDB | ✅ None (CryptoKit) | ✅ Apple framework |
| **Debugging** | ✅ Easy (text files) | ❌ Hard (encrypted) | ❌ Hard (encrypted) | ❌ Hard (encrypted) | ⚠️ Medium (Xcode tools) |
| **Industry Use** | ⚠️ Small apps | ✅ Signal, WhatsApp | ✅ Day One, Bear | ⚠️ Rare | ✅ Many apps |
| **Maintenance** | ✅ Minimal | ⚠️ Manual SQL | ✅ Migrations built-in | ✅ Minimal | ⚠️ Schema changes hard |

---

## Recommendation

**For Edge Debug Helper:**

### Recommended: Option 2 (GRDB + SQLCipher)
- **Why:** Best balance of security, performance, and developer experience
- **Security:** Full encryption at rest with AES-256
- **Performance:** Indexed queries, no full table scans
- **Type Safety:** Swift structs, not raw SQL strings
- **Maintenance:** Well-maintained, used by professional apps
- **Timeline:** 5-7 days
- **Risk:** Low (mature, battle-tested library)

**Since there's no existing data to migrate, we can implement the best solution from day one without compromise.**

### Not Recommended:
- **Option 1 (Raw SQLCipher):** Too verbose, error-prone
- **Option 3 (Encrypted JSON):** Would need migration later anyway
- **Option 4 (Core Data):** Overkill for simple cache data

---

## Implementation Path

**IMPORTANT:** No migration needed - JSON support never shipped to users. This is a fresh implementation.

### Recommended: Direct to GRDB + SQLCipher
```
No existing data → GRDB + SQLCipher (5-7 days)
```
- Best-in-class solution from day one
- No technical debt from incremental approach
- Professional-grade security and performance

---

## Decision Criteria

**Choose Encrypted JSON if:**
- Need security improvement ASAP
- Want minimal code changes
- Have limited time budget

**Choose GRDB + SQLCipher if:**
- Have 1-2 weeks for implementation
- Want best-in-class solution
- Performance matters (large datasets)
- Want type-safe queries

**Choose to stay with JSON if:**
- Security not a primary concern
- Datasets remain small (<1000 items)
- Want simplest possible approach

---

## Next Actions

**Recommended: Proceed with GRDB + SQLCipher**

1. **Add GRDBCipher package** (1 hour)
   - Open Xcode → File → Add Package Dependencies
   - URL: `https://github.com/groue/GRDB.swift`
   - Product: **GRDBCipher** (NOT GRDB)
   - Target: Edge Debug Helper

2. **Complete Phase 1: Verify SQLCipherService** (1 hour)
   - Update import: `import GRDBCipher`
   - Build and verify compilation
   - Review implementation

3. **Phase 2: Update repositories** (2-3 days)
   - DatabaseRepository
   - SubscriptionsRepository
   - HistoryRepository
   - FavoritesRepository
   - ObservableRepository

4. **Phase 3: Test isolation** (0.5 days)
   - Extend test detection to Ditto databases

5. **Phase 4: Testing** (2-3 days)
   - Unit tests for SQLCipherService
   - Integration tests for repositories
   - Manual testing

**Total Timeline:** 5-7 days
