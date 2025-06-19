# macOS App Release Automation

This directory contains everything needed to automatically build and release your macOS SwiftUI app using GitHub Actions.

## What's Been Set Up

### 1. GitHub Actions Workflow
- **File**: `.github/workflows/macos-release.yml`
- **Purpose**: Automatically builds and releases your app when you push a new tag
- **Triggers**: Pushes to tags matching `v*` (e.g., `v1.0.0`, `v2.1.3`)

### 2. Export Options Configuration
- **File**: `SwiftUI/exportOptions.plist`
- **Purpose**: Configures how Xcode exports your app from the archive
- **Settings**: Developer ID distribution, manual signing, your team ID

### 3. Certificate Export Script
- **File**: `SwiftUI/scripts/export-certificate.sh`
- **Purpose**: Helps you export your Developer ID certificate for GitHub Actions
- **Usage**: Run this script to export and convert your certificate to base64

### 4. Setup Documentation
- **File**: `SwiftUI/RELEASE_SETUP.md`
- **Purpose**: Comprehensive guide for setting up certificates and GitHub secrets

## Quick Start

### 1. Prerequisites
- Apple Developer account with Developer ID Application certificate
- GitHub repository with Actions enabled

### 2. Set Up GitHub Secrets
Add these secrets to your GitHub repository:

| Secret Name | Description |
|-------------|-------------|
| `MACOS_P12_BASE64` | Base64-encoded Developer ID certificate |
| `MACOS_P12_PASSWORD` | Password for the exported certificate |
| `KEYCHAIN_PASSWORD` | Random password for temporary keychain |
| `DEVELOPMENT_TEAM` | Your Apple Developer Team ID |

### 3. Export Your Certificate
```bash
cd SwiftUI
./scripts/export-certificate.sh
```

### 4. Create a Release
```bash
# Update version in Xcode
git add .
git commit -m "Prepare for release v1.0.0"
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

## What the Workflow Does

1. **Triggers** on tag push (e.g., `v1.0.0`)
2. **Sets up** macOS runner with latest Xcode
3. **Configures** code signing with your certificate
4. **Builds** your app for release (ARM64)
5. **Exports** the app from archive
6. **Creates** a DMG installer with Applications folder link
7. **Creates** a GitHub release
8. **Uploads** the DMG as a release asset

## File Structure

```
SwiftUI/
├── .github/workflows/macos-release.yml  # GitHub Actions workflow
├── exportOptions.plist                   # Xcode export configuration
├── scripts/
│   └── export-certificate.sh            # Certificate export helper
├── RELEASE_SETUP.md                     # Detailed setup guide
└── README_RELEASE.md                    # This file
```

## Troubleshooting

### Common Issues

1. **Build Fails**
   - Check that all Swift Package dependencies are resolved
   - Verify the scheme name is exactly "Edge Studio"
   - Ensure your Team ID is correct in `exportOptions.plist`

2. **Code Signing Errors**
   - Verify your certificate is valid and not expired
   - Check that the p12 password is correct
   - Ensure the certificate is a Developer ID Application type

3. **DMG Creation Fails**
   - Check that the app builds successfully first
   - Verify the app bundle name is "Edge Studio.app"

### Getting Help

1. Check the GitHub Actions logs for specific error messages
2. Verify your Apple Developer account status
3. Test the build process locally in Xcode first
4. Review the detailed setup guide in `RELEASE_SETUP.md`

## Security Notes

- Never commit certificates or passwords to your repository
- Use GitHub secrets for all sensitive information
- Regularly rotate your certificates and passwords
- The workflow uses temporary keychains that are cleaned up automatically

## Customization

You can modify the workflow to:
- Add notarization for distribution outside the App Store
- Build for multiple architectures (Intel + ARM)
- Add additional release assets
- Change the trigger conditions
- Customize the DMG creation process

## Next Steps

1. Follow the setup guide in `RELEASE_SETUP.md`
2. Export your certificate using the provided script
3. Add the required GitHub secrets
4. Test with a small version bump
5. Create your first release!

---

For detailed instructions, see `RELEASE_SETUP.md` 