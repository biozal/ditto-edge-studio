# App Release Setup Guide

This guide explains how to set up automated releases for Edge Studio.

# MacOS 

## Overview

The workflow will:
1. Build the for release when a new tag is pushed
2. Code sign the app with the Developer ID certificate
3. Create a DMG installer
4. Upload the DMG as a release asset

## Prerequisites

### 1. Apple Developer Account
You need access to the Apple Developer account with:
- Developer ID Application certificate
- App-specific password for GitHub Actions

### 2. Code Signing Certificate
You need the Developer ID Application certificate for code signing - you can have XCode auto create it or manually create it:

1. Open **Keychain Access** on your Mac
2. Go to **Keychain Access** → **Certificate Assistant** → **Request a Certificate From a Certificate Authority**
3. Fill in your email and name
4. Select **Developer ID Application** as the certificate type
5. Submit the request to Apple
6. Download and install the certificate

### 3. Export Certificate for GitHub Actions

1. In **Keychain Access**, find your Developer ID Application certificate
2. Right-click and select **Export**
3. Choose **Personal Information Exchange (.p12)** format
4. Set a password for the export
5. Convert to base64 for GitHub secrets:

```bash
base64 -i your-certificate.p12 | pbcopy
```

## GitHub Secrets Setup

Add these secrets to your GitHub repository:

### Required Secrets

1. **`MACOS_P12_BASE64`**
   - Value: The base64-encoded p12 certificate (from the export step above)

2. **`MACOS_P12_PASSWORD`**
   - Value: The password you set when exporting the p12 file

3. **`KEYCHAIN_PASSWORD`**
   - Value: A random password for the temporary keychain (e.g., `my-secure-keychain-password`)

4. **`DEVELOPMENT_TEAM`**
   - Value: Your Apple Developer Team ID (found in your Apple Developer account)

### How to Add Secrets

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with the appropriate name and value

## Using the Workflow

### Creating a Release

1. **Update the app version** in Xcode project settings
2. **Commit and push** your changes
3. **Create and push a tag**:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow will automatically:
- Build your app
- Create a DMG installer
- Create a GitHub release
- Upload the DMG as a release asset

### Tag Naming Convention

Use semantic versioning:
- `v1.0.0` - Major release
- `v1.1.0` - Minor release  
- `v1.0.1` - Patch release

## Troubleshooting

### Common Issues

1. **Code Signing Errors**
   - Ensure your certificate is valid and not expired
   - Check that the Team ID matches your Apple Developer account
   - Verify the p12 password is correct

2. **Build Failures**
   - Check that all dependencies are properly configured
   - Ensure the scheme name matches exactly: "Edge Studio"
   - Verify the project structure is correct

3. **DMG Creation Issues**
   - Ensure the app builds successfully before DMG creation
   - Check that the app bundle name matches: "Edge Studio.app"

### Debugging

To debug the workflow:
1. Go to **Actions** tab in your GitHub repository
2. Click on the failed workflow run
3. Check the logs for specific error messages

## Security Notes

- Never commit certificates or passwords 
- Regularly rotate certificates and passwords

## Additional Configuration

### Customizing the Workflow

You can modify the workflow file (`.github/workflows/macos-release.yml`) to:
- Change the trigger conditions
- Add additional build configurations
- Customize the DMG creation process
- Add additional release assets