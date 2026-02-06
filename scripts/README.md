# Build & Notarization Scripts

This folder contains scripts for building and notarizing Edge Debug Helper for macOS distribution.

## Prerequisites

### 1. Developer ID Certificate
You need a valid "Developer ID Application" certificate from Apple. Check if you have one:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

✅ **Found:** `Developer ID Application: Aaron LaBeau (E3FRN9JNGJ)`

### 2. Apple ID with App-Specific Password
For notarization, you need:
- An Apple ID enrolled in the Apple Developer Program
- An app-specific password (generated at appleid.apple.com)

### 3. Store Notarization Credentials
Store your credentials in the keychain (one-time setup):

```bash
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id your-email@example.com \
  --team-id E3FRN9JNGJ \
  --password <app-specific-password>
```

This stores your credentials securely in the macOS keychain.

---

## Quick Start

### Option 1: Simple Release Build (No Notarization)
```bash
./build-release.sh
```

This builds the release version and places it in `build/Release/`. Use this for local testing.

### Option 2: Full Release with Notarization
```bash
./build-and-notarize.sh
```

This:
1. Builds the release version
2. Creates an archive
3. Exports a signed app
4. Creates a DMG
5. Submits to Apple for notarization
6. Staples the notarization ticket

The final DMG will be in the `scripts/` folder.

---

## Manual Notarization Process

If you want to notarize manually:

### 1. Build the app
```bash
./build-release.sh
```

### 2. Code sign the app
```bash
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Aaron LaBeau (E3FRN9JNGJ)" \
  "build/Release/Edge Debug Helper.app"
```

### 3. Create a DMG
```bash
hdiutil create -volname "Edge Debug Helper" \
  -srcfolder "build/Release/Edge Debug Helper.app" \
  -ov -format UDZO \
  "scripts/EdgeDebugHelper.dmg"
```

### 4. Submit for notarization
```bash
xcrun notarytool submit scripts/EdgeDebugHelper.dmg \
  --keychain-profile "notarytool-profile" \
  --wait
```

### 5. Check notarization status
```bash
# Get the submission ID from the previous command
xcrun notarytool info <submission-id> \
  --keychain-profile "notarytool-profile"
```

### 6. Staple the ticket (after approval)
```bash
xcrun stapler staple scripts/EdgeDebugHelper.dmg
```

### 7. Verify stapling
```bash
xcrun stapler validate scripts/EdgeDebugHelper.dmg
spctl -a -vvv -t install scripts/EdgeDebugHelper.dmg
```

---

## Notarization Timeline

- **Submission:** Instant
- **Processing:** Usually 5-30 minutes
- **Result:** Approved or Rejected

You'll receive an email from Apple with the notarization result.

---

## Troubleshooting

### "App is damaged" error
This happens when the app isn't notarized or the staple is missing:
```bash
# Remove quarantine flag (for testing only)
xattr -d com.apple.quarantine "Edge Debug Helper.app"
```

### Notarization rejected
Check the detailed log:
```bash
xcrun notarytool log <submission-id> \
  --keychain-profile "notarytool-profile"
```

Common issues:
- Hardened runtime not enabled
- Missing entitlements
- Unsigned frameworks
- Insecure code

### Certificate issues
Verify your certificate:
```bash
security find-identity -v -p codesigning
codesign -dv --verbose=4 "Edge Debug Helper.app"
```

---

## Distribution

Once notarized and stapled:

1. **Test locally:** Open the DMG and verify it runs without warnings
2. **Upload:** Share via GitHub Releases, website, etc.
3. **Users:** They can download and run without "unidentified developer" warnings

---

## Build Output

After running scripts, you'll find:

```
ditto-edge-studio/
├── scripts/
│   ├── EdgeDebugHelper-v0.2.4.dmg  # Final distributable
│   ├── build-and-notarize.sh       # Full build script
│   ├── build-release.sh            # Simple build script
│   └── README.md                   # This file
└── build/
    ├── EdgeDebugHelper.xcarchive   # Archive
    ├── export/
    │   └── Edge Debug Helper.app   # Exported app
    └── Release/
        └── Edge Debug Helper.app   # Direct build
```

---

## References

- [Apple Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [notarytool Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)
- [Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Introduction/Introduction.html)

---

## Support

For notarization issues, contact Apple Developer Support or check the Apple Developer Forums.

For app-specific issues, see the main project README.
