# Release Setup Guide

How to cut a GitHub release of Edge Studio for **macOS** (signed + notarized DMG)
and **Android** (signed, sideloadable APK).

Releases are built locally and uploaded manually — there is no CI. The repo has
no `.github/workflows/`; the Xcode Cloud flow described in earlier versions of
this document is no longer used.

---

## macOS

### Prerequisites

| Requirement | How to verify |
|---|---|
| Xcode 26.2+ | `xcodebuild -version` |
| `Developer ID Application` certificate | `security find-identity -v -p codesigning` |
| `notarytool-profile` keychain credential | `xcrun notarytool history --keychain-profile notarytool-profile` |

The notarization credential is **not** your Apple ID password. Generate an
app-specific password at <https://appleid.apple.com> → Sign-In and Security →
App-Specific Passwords, then store it once:

```bash
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id <your-apple-id> \
  --team-id E3FRN9JNGJ
```

### Two non-obvious build flags

`scripts/build-and-notarize.sh` already sets these. If you invoke `xcodebuild`
by hand, you still need both or the archive fails:

- **`ARCHS=arm64`** — `DittoSwift.xcframework` ships a `macos-arm64` slice only.
  Release otherwise defaults to `ARCHS_STANDARD` (arm64 + x86_64) and the
  x86_64 pass dies with a missing-slice error. **Edge Studio for macOS is
  Apple Silicon only**; there is no Intel build.
- **`-destination "generic/platform=macOS"`** — `SUPPORTED_PLATFORMS` lists
  `iphoneos` first, so an unqualified `archive` builds against the iOS SDK and
  fails with "requires a provisioning profile". Note that
  `-destination "platform=macOS,arch=arm64"` does *not* constrain `ARCHS`
  during `archive`, only during `build`.

### Cutting the build

```bash
./scripts/build-and-notarize.sh
```

This archives, exports with the `developer-id` method, builds a DMG with an
`/Applications` symlink, then prompts to submit for notarization and staple the
ticket. Output lands in `scripts/Ditto Edge Studio <version>.dmg`.

Verify before uploading:

```bash
spctl -a -vvv -t install "/Volumes/Ditto Edge Studio <version>/Ditto Edge Studio.app"
xcrun stapler validate "scripts/Ditto Edge Studio <version>.dmg"
```

`scripts/build-release.sh` is the same flow **without** notarization. Use it for
local smoke tests only — a DMG from it will trip Gatekeeper on other machines.

---

## Android

### Signing

Release signing reads `android/keystore.properties`, which is **gitignored** and
points at a keystore stored outside the repo:

```properties
storeFile=/Users/<you>/.keystores/ditto-edge-studio-release.jks
storePassword=...
keyAlias=ditto-edge-studio
keyPassword=...
```

If that file or the keystore is missing, `assembleRelease` still succeeds but
emits an **unsigned** APK that no device will install. That is intentional —
contributors and CI can build without holding release keys — so always verify
the output before shipping it (see below).

> **Back up the keystore and its password.** Android identifies an app by its
> signing key. Lose the key and you can never ship an upgrade to an installed
> APK — users would have to uninstall and lose their local data. Store both in
> a password manager.

### ABI

The release build ships **`arm64-v8a` only** (`ndk { abiFilters }` in
`android/app/build.gradle.kts`). A universal APK is ~316 MB because
`libdittoffi.so` is ~55 MB per ABI; restricting to arm64-v8a cuts it to ~131 MB
while still covering every real device from roughly the last decade and Apple
Silicon emulators. Debug builds keep all ABIs so Intel emulators still work.

### Cutting the build

```bash
cd android && ./gradlew assembleRelease
```

Output: `android/app/build/outputs/apk/release/app-release.apk`.

**Always verify it is actually signed** before uploading:

```bash
BT=$(ls -d ~/Library/Android/sdk/build-tools/* | sort -V | tail -1)
"$BT/apksigner" verify --print-certs -v app/build/outputs/apk/release/app-release.apk
```

A filename of `app-release-unsigned.apk`, or `DOES NOT VERIFY`, means signing
did not run — check `keystore.properties`.

---

## Versioning

Bump these together; they must agree:

| Platform | File | Fields |
|---|---|---|
| macOS/iPadOS | `SwiftUI/Edge Debug Helper.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` |
| Android | `android/app/build.gradle.kts` | `versionName`, `versionCode` |

`versionCode` must increase monotonically on every Android release, even for a
beta — Android refuses to install an APK whose `versionCode` is lower than the
installed one.

---

## Publishing

```bash
git tag -a v1.0b5 -m "Edge Studio v1.0 Beta 5"
git push origin v1.0b5

gh release create v1.0b5 \
  --title "Edge Studio v1.0 Beta 5" \
  --notes-file RELEASE_NOTES_v1.0b5.md \
  "scripts/Ditto Edge Studio 1.0b5.dmg" \
  "android/app/build/outputs/apk/release/app-release.apk#EdgeStudio-1.0b5-arm64.apk"
```

Because the Android APK is signed with a self-generated key rather than one
Google distributes, sideloaders must enable "Install unknown apps" for their
browser or file manager. Say so in the release notes.
