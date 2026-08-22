# Credential Storage — current state and required remediation

> **The local configuration store is NOT encrypted, despite its name.** Database
> tokens, offline license tokens, shared secret keys and HTTP API keys are stored in
> plaintext SQLite. Treat this as an open security issue, not a solved one.

## Evidence

Verified 2026-08-20, independently by two reviewers:

```
$ grep -ci sqlcipher "SwiftUI/Edge Debug Helper.xcodeproj/project.pbxproj" \
      "SwiftUI/.../swiftpm/Package.resolved"
0
0

$ head -4 SwiftUI/EdgeStudio/Data/SQLCipherService.swift
import Foundation
import LocalAuthentication
import SQLite3          # ← Apple's system libsqlite3, not SQLCipher

$ head -c 16 "~/Library/Containers/.../ditto_edge_studio/ditto_encrypted.db" | xxd
00000000: 5351 4c69 7465 2066 6f72 6d61 7420 3300   SQLite format 3.
```

A SQLCipher database has a random-looking header with **no** `SQLite format 3` magic.
This file has the magic, so it is a plain SQLite database.

`SQLCipherService.initialize()` issues `PRAGMA key`, `cipher_page_size`,
`cipher_use_hmac` and `cipher_memory_security`. System SQLite **silently ignores
unknown pragmas**, so all four are no-ops. One reviewer opened the live production
database with the stock `sqlite3` CLI, with no key, and read the `databaseConfigs`
schema and rows.

## What is and is not protected

Corrected 2026-08-22 after the readiness review measured this rather than assuming it. The
earlier version of this table credited `0600` on the database file; the database file is
`0644`. The **conclusion is unchanged** — the protection is the container, not the file mode.

| Layer | Status |
|---|---|
| Database file contents | **Plaintext.** Any process with file access reads every credential. |
| Database file permissions | **`0644`** (`-rw-r--r--`), measured. Nothing in the codebase `chmod`s it — the only `setAttributes` call is on the key file (`SQLCipherService.getOrCreateEncryptionKey`). |
| Key file (`sqlcipher.key`) | `0600`, plus `.completeFileProtection` (a no-op on macOS). Protects a key that encrypts nothing. |
| macOS app sandbox | **This is the actual protection.** The whole chain is `drwx------`: `~/Library/Containers/<bundle-id>/` → `Data/Library/Application Support/`. Other sandboxed apps cannot reach it; any process running as this user can. |
| Unencrypted backups / disk images | Credentials included. |

**Where the files actually live** (they are container-relative, not under
`~/Library/Application Support` — a distinction that has already sent one documented
recovery command to a path that does not exist):

```
~/Library/Containers/<bundle-id>/Data/Library/Application Support/ditto_edge_studio/            # production
~/Library/Containers/<bundle-id>/Data/Library/Application Support/ditto_edge_studio_test/       # UI tests
~/Library/Containers/<bundle-id>/Data/Library/Application Support/ditto_edge_studio_unit_test/  # unit tests
```

## Why this was not caught

`verifyEncryption()` prepared `SELECT 1` and never stepped it. `SELECT 1` touches no
page, so it could not detect a wrong key — or the absence of encryption — despite its
error message reading "Wrong key or corrupted database". It now reads `sqlite_master`
and steps the statement, which at least proves the file is readable. **It still cannot
prove the file is encrypted**, and its doc comment says so.

## Remediation options

Deliberately **not** applied as a drive-by change: each alters the on-disk format or
the key lifecycle for existing installs, and needs a migration plan plus a decision
about existing plaintext databases in the field.

1. **Link SQLCipher** (matches the current design and class name). Add a SQLCipher SPM
   product, replace `import SQLite3`, and keep the existing `PRAGMA key` calls — which
   then start working. Requires: a migration that reads each existing plaintext store
   and rewrites it encrypted (`sqlcipher_export`), and a decision on failure handling.
2. **Move only the secrets to the Keychain** and leave metadata in SQLite. Smaller
   blast radius, no file-format change, and Keychain gives hardware protection on
   Apple silicon. Requires a one-time migration of the five credential columns
   (`token`, `authUrl`, `httpApiUrl`, `httpApiKey`, `secretKey`) and a rewrite of the
   read/write paths.
3. **Rename and re-document, protecting nothing further.** Only defensible if the
   threat model genuinely accepts plaintext local credentials — in which case the class
   name, file name (`ditto_encrypted.db`) and doc comments must stop claiming
   otherwise.

Option 2 is the smallest correct fix; option 1 preserves the current architecture.

## Interim honesty requirements (done)

- `SQLCipherService`'s class documentation no longer claims "256-bit AES encryption of
  all local cache data" or "Database file encrypted at rest with AES-256".
- `verifyEncryption()` actually executes, and its comment states what it cannot prove.
- An existing-but-unreadable key file is now a hard error instead of triggering key
  regeneration, which used to make the store permanently unreadable.

Until one of the remediation options ships, **treat any machine with a compromised
user account as having disclosed every Ditto credential entered into this app.**

## Decision (2026-08-21) — option 3 for this release, option 1 as a tracked follow-up

**Chosen: option 3.** Accept plaintext local storage for this release, remove every
claim to the contrary, and file option 1 (link a real SQLCipher product + an
`sqlcipher_export` migration) as a separate piece of work with its own plan and review
cycle. This does **not** block the release of the Advanced Database Configuration change
set. Recorded in full, with the counter-arguments, in
`plans/2026-08-21-production-readiness-remediation.md` §2.D1.

Why, in short:

1. **Not a regression.** The store was plaintext before that work began, and the two
   columns it adds (`collectionSyncScopes`, `startupSettings`) hold collection names and
   tuning parameters, not secrets. Blocking a feature on a pre-existing platform issue it
   did not worsen is the wrong gate.
2. **Options 1 and 2 are each larger and riskier than everything else in that plan
   combined**, and both change the on-disk format or the key lifecycle for existing
   installs. The key file's threat trace has already produced one data-destruction path on
   this repository; that is not work to bundle into a review of something else.
3. **The dishonesty was the part fixable now, cheaply and verifiably** — and that is what
   shipped.

### What shipped under this decision

- Every "encrypted at rest with AES-256 (SQLCipher)" claim in code is gone. The five
  repositories (`DatabaseRepository`, `HistoryRepository`, `FavoritesRepository`,
  `SubscriptionsRepository`, `ObservableRepository`) and `SQLCipherService` now state that
  the store is **not** encrypted and point here. The verification is a case-insensitive
  `grep -rniE "encrypt"` over those files, read rather than counted: every surviving hit is
  either a denial or a pointer to this document.
- `SQLCipherService`'s stale Keychain-era doc comment on `getOrCreateEncryptionKey` is
  deleted. It described `kSecAttrAccessibleAfterFirstUnlock` and the Secure Enclave for an
  implementation that has not used the Keychain in a long time, and it was the actual
  source of a review finding against the file-protection class (which is deliberate, and
  unchanged).
- The `rotateEncryptionKey` doc comment now says why it cannot be implemented as written:
  `PRAGMA rekey` is another silent no-op on Apple's system SQLite.
- The integration test named `Credentials stored encrypted at rest` is renamed
  `Credentials round-trip through the local store`, with a comment stating that it cannot
  prove encryption and what an assertion that could would look like (it would fail today).

### Deliberately deferred to the option-1 follow-up

- **Renaming the type** (`SQLCipherService` → e.g. `LocalConfigurationStore`) and its
  companions (`SQLCipherError`, `SQLCipherContext`, the test files). The type declaration
  already carries an unmissable `⚠️ THE STORE IS NOT CURRENTLY ENCRYPTED` header, so it no
  longer misleads a reader; the rename is a large cosmetic diff with no security benefit,
  and option 1 replaces the implementation anyway.
- **Renaming the on-disk file** (`ditto_encrypted.db`). The migration's failure mode is
  losing every stored credential — a real data-destruction risk for a filename no user
  sees. Option 1 rewrites the file regardless.

**Reversing this decision** means doing option 1 or 2 as its own planned change; it is not
a tweak to the work above.
