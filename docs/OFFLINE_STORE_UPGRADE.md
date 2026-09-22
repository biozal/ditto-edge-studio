# Offline store adoption

Before this release, small-peer-only databases used Ditto's default persistence
directory even though Edge Studio created its own empty database directory.
The SDK 5.1 default is `Ditto.defaultRootDirectory/ditto-<databaseId>` with the
database ID's original case. Older SDK documentation described a lowercase ID.

Opening a small-peer-only database now checks those two exact legacy paths before
opening the SDK at Edge Studio's resolved `database/` directory. A single populated
legacy directory is moved in its entirety when the destination is absent or empty.
This preserves documents, attachments, SDK identity, and offline license state.
Case aliases on case-insensitive filesystems count as one source. Reopening uses
the adopted directory. Development-mode and UI-test opens never adopt legacy data.

If both the destination and a legacy directory contain data, or both distinct
legacy paths contain data, opening stops with an error listing the paths. No copy
is overwritten or merged. Back up all copies before reconciling them. Filesystem
errors also stop opening; the app must not silently create a fresh offline store
after an adoption failure.

`PersistenceDirectoryPreparationTests` exercises the production helper with
temporary fixture directories, including old empty destinations and conflicting
copies. It does not open Ditto or inspect existing user stores. A separate SDK 5.1 probe created a fresh default store, adopted it with the
production helper, reopened it and verified the same peer identity and resolved
persistence path. Large pre-existing document sets, filesystem permission errors
and in-app ambiguity presentation remain separate validation requirements. No
existing user store was opened for these checks.
