# SQLCipher Setup Guide

This guide explains how to add SQLCipher to the Edge Debug Helper project for encrypted database support.

## What is SQLCipher?

SQLCipher is an SQLite extension that provides transparent 256-bit AES encryption of database files. It's used by Signal, WhatsApp, and many other security-focused applications.

## Why SQLCipher?

The current JSON file storage is unencrypted at rest. SQLCipher provides:
- **256-bit AES encryption** - Military-grade encryption
- **Hardware acceleration** - Uses macOS Secure Enclave on M1+ Macs
- **ACID transactions** - Data integrity guarantees
- **Foreign key constraints** - Cascade deletion
- **Better performance** - Indexed queries vs. loading entire JSON files

## Installation Options

### Option 1: Using GRDB.swift with SQLCipher (RECOMMENDED)

**Why GRDB?**
- Well-maintained, active development
- Excellent SQLCipher support out of the box
- Type-safe Swift API (no raw SQL needed)
- Better error handling and migrations
- Used by major apps (Day One, Bear, etc.)

**Installation:**

1. Open `Edge Debug Helper.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/groue/GRDB.swift`
4. Select version: **Latest** (6.x.x)
5. Add **GRDBCipher** product to target: **Edge Debug Helper**
   - ⚠️ **IMPORTANT:** Select **GRDBCipher**, NOT **GRDB**!
   - GRDBCipher includes SQLCipher encryption
   - GRDB is plain SQLite without encryption

6. Add to target: **Edge Debug Helper**

**Build Settings (Required):**

No additional build settings needed! GRDBCipher includes everything pre-configured.

**Code Changes:**

Replace the import in `SQLCipherService.swift`:
```swift
// OLD
import Foundation
import SQLite3

// NEW
import Foundation
import GRDBCipher
```

Then update the service to use GRDB's API instead of raw SQLite3 calls.

**Pros:**
- ✅ Zero build configuration needed
- ✅ Type-safe Swift API
- ✅ Excellent documentation and examples
- ✅ Active maintenance
- ✅ Battle-tested in production apps

**Cons:**
- ⚠️ API is different from raw SQLite3 (requires code changes)
- ⚠️ Larger framework size

### Option 2: Using SQLCipher C Library Directly

**Why raw SQLCipher?**
- Minimal dependencies
- Direct control over encryption
- Same API as SQLite3 (easier migration)

**Installation:**

1. Add SQLCipher via Homebrew:
   ```bash
   brew install sqlcipher
   ```

2. Open `Edge Debug Helper.xcodeproj` in Xcode

3. Add build settings:

   **A. Build Settings → Header Search Paths**
   ```
   /opt/homebrew/opt/sqlcipher/include
   ```

   **B. Build Settings → Library Search Paths**
   ```
   /opt/homebrew/opt/sqlcipher/lib
   ```

   **C. Build Settings → Other Linker Flags**
   ```
   -lsqlcipher
   -framework Security
   ```

   **D. Build Settings → Preprocessor Macros**
   ```
   SQLITE_HAS_CODEC=1
   SQLITE_TEMP_STORE=2
   SQLITE_THREADSAFE=1
   SQLITE_ENABLE_FTS5=1
   ```

4. Create a bridging header or use a module map

**Module Map Approach (Recommended):**

Create `SwiftUI/Edge Debug Helper/SQLCipher.modulemap`:
```
module SQLCipher [system] {
    header "/opt/homebrew/opt/sqlcipher/include/sqlcipher/sqlite3.h"
    link "sqlcipher"
    export *
}
```

Add to **Build Settings → Import Paths**:
```
$(PROJECT_DIR)/Edge Debug Helper
```

**Code Changes:**

Update import in `SQLCipherService.swift`:
```swift
// OLD
import SQLite3

// NEW
import SQLCipher
```

**Pros:**
- ✅ Minimal dependencies
- ✅ Same API as SQLite3 (current code works)
- ✅ Smaller binary size

**Cons:**
- ❌ Requires Homebrew installation
- ❌ Manual build configuration (complex)
- ❌ Breaks on different machines if paths change

### Option 3: Using SQLCipher SPM Package (NOT RECOMMENDED)

**Why not recommended?**
- ⚠️ Official SQLCipher SPM package is not well-maintained
- ⚠️ Complex build settings required
- ⚠️ May not support latest Xcode/Swift versions

**If you still want to try:**

1. Add package: `https://github.com/sqlcipher/SQLCipher.swift`
2. Follow the build settings from the repo README

## Recommendation

**Use Option 1 (GRDB.swift with SQLCipher)** for this project.

**Reasons:**
1. Zero build configuration headaches
2. Type-safe Swift API (better than raw SQL strings)
3. Excellent migration support
4. Active maintenance and community support
5. Used by professional macOS apps

**Migration to GRDB:**

Instead of raw SQL:
```swift
// Current (raw SQLite3)
var statement: OpaquePointer?
sqlite3_prepare_v2(db, "SELECT * FROM users WHERE id = ?", -1, &statement, nil)
sqlite3_bind_int(statement, 1, userId)
sqlite3_step(statement)
// ... extract values ...
sqlite3_finalize(statement)
```

With GRDB:
```swift
// GRDB (type-safe)
let user = try User.fetchOne(db, key: userId)
```

**Implementation Plan with GRDB:**

1. Add GRDBCipher package
2. Rewrite `SQLCipherService` to use GRDB API
3. Define Swift structs that conform to `Codable` and `FetchableRecord`
4. Use GRDB's migrations for schema management
5. Use GRDB's query builders instead of raw SQL strings

**Example GRDB Implementation:**

```swift
import GRDBCipher

actor SQLCipherService {
    static let shared = SQLCipherService()

    private var dbQueue: DatabaseQueue?

    func initialize() async throws {
        let dbPath = try getDatabasePath()
        let key = try await getOrCreateEncryptionKey()

        var config = Configuration()
        config.prepareDatabase { db in
            try db.usePassphrase(key)  // SQLCipher encryption
        }

        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        try await dbQueue?.write { db in
            try db.create(table: "databaseConfigs") { t in
                t.primaryKey("_id", .text)
                t.column("name", .text).notNull()
                t.column("databaseId", .text).notNull().unique()
                t.column("mode", .text).notNull()
                // ... other columns
            }
        }
    }

    func getAllDatabaseConfigs() async throws -> [DatabaseConfig] {
        try await dbQueue?.read { db in
            try DatabaseConfig.fetchAll(db)
        } ?? []
    }
}

struct DatabaseConfig: Codable, FetchableRecord, PersistableRecord {
    var _id: String
    var name: String
    var databaseId: String
    var mode: String
    // ... other properties
}
```

## Verification

After adding SQLCipher, verify it works:

1. Build the project (⌘B)
2. Run the app
3. Check logs for:
   ```
   SQLCipher initialized successfully (schema version 1)
   ```

4. Verify database file is encrypted:
   ```bash
   # Try to open with regular sqlite3 (should fail)
   sqlite3 ~/Library/Application\ Support/ditto_cache/ditto_encrypted.db "SELECT * FROM databaseConfigs"
   # Should output: "file is not a database"
   ```

5. Check encryption key in Keychain:
   - Open **Keychain Access.app**
   - Search for: `sqlcipher_master_key`
   - Should exist in login keychain

## Troubleshooting

### "No such module 'SQLCipher'"
- Verify package was added correctly
- Clean build folder (⌘⇧K)
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`

### "Undefined symbol: sqlite3_key_v2"
- Using system SQLite3 instead of SQLCipher
- Check that SQLCipher is linked (not SQLite3)
- Verify build settings include SQLCipher paths

### "file is not a database" error
- Encryption key is wrong
- Key not set before opening database
- Database corrupted

### Performance issues
- Add indexes to frequently queried columns
- Use WAL mode (already enabled in code)
- Consider connection pooling for high concurrency

## Next Steps

1. Choose and implement one of the options above
2. Run tests to verify encryption works
3. Continue with Phase 2: Repository Migration
4. Implement data migration from JSON files

## References

- [GRDB.swift Documentation](https://github.com/groue/GRDB.swift)
- [SQLCipher Official Docs](https://www.zetetic.net/sqlcipher/)
- [SQLCipher SPM Package](https://github.com/sqlcipher/SQLCipher.swift)
- [Apple Security Framework](https://developer.apple.com/documentation/security)
