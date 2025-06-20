# Troubleshooting Code Signing Issues

## Current Error
```
No signing certificate "Developer ID Application" found: No "Developer ID Application" signing certificate matching team ID "***" with a private key was found.
```

## Common Causes and Solutions

### 1. Certificate Export Issues

**Problem**: The certificate wasn't exported correctly from Keychain Access.

**Solution**: 
1. Open Keychain Access on your Mac
2. Find your Developer ID Application certificate
3. Right-click → Export
4. Choose "Personal Information Exchange (.p12)"
5. Set a password
6. Convert to base64:
   ```bash
   base64 -i your-certificate.p12 | pbcopy
   ```

### 2. Wrong Certificate Type

**Problem**: You might have exported the wrong certificate type.

**Solution**: Make sure you're exporting a **Developer ID Application** certificate, not:
- Apple Development
- Apple Distribution
- Mac App Distribution

### 3. Team ID Mismatch

**Problem**: The certificate doesn't match your team ID.

**Solution**: 
1. Check your Apple Developer account for the correct Team ID
2. Verify the certificate was issued to your team
3. Update the `DEVELOPMENT_TEAM` secret in GitHub

### 4. Certificate Expired or Invalid

**Problem**: The certificate has expired or is invalid.

**Solution**:
1. Check certificate validity in Keychain Access
2. Request a new Developer ID Application certificate from Apple
3. Export and update the GitHub secret

## Debugging Steps

### Step 1: Verify Certificate Locally
Run this on your Mac to check available certificates:
```bash
security find-identity -v -p codesigning login.keychain
```

Look for a line like:
```
1) 1234567890ABCDEF "Developer ID Application: Your Name (TEAM_ID)"
```

### Step 2: Test Certificate Export
Use the provided script:
```bash
cd SwiftUI
./scripts/export-certificate.sh
```

### Step 3: Check GitHub Secrets
Verify these secrets are set correctly:
- `MACOS_P12_BASE64`: Base64-encoded certificate
- `MACOS_P12_PASSWORD`: Password for the p12 file
- `KEYCHAIN_PASSWORD`: Random password for temporary keychain
- `DEVELOPMENT_TEAM`: Your Apple Developer Team ID

### Step 4: Test Build Locally
Try building locally with the same settings:
```bash
cd SwiftUI
xcodebuild -project "Edge Studio.xcodeproj" \
  -scheme "Edge Studio" \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  archive \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE="Manual" \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID"
```

## Alternative Approaches

### Option 1: Use Automatic Code Signing
If you have issues with manual signing, try automatic:
```yaml
CODE_SIGN_STYLE="Automatic"
CODE_SIGN_IDENTITY=""
```

### Option 2: Skip Code Signing for Testing
For testing purposes, you can skip code signing:
```yaml
CODE_SIGN_IDENTITY=""
CODE_SIGN_STYLE="Manual"
CODE_SIGNING_ALLOWED="NO"
```

### Option 3: Use Different Certificate
If you have multiple certificates, try using a different one:
```yaml
CODE_SIGN_IDENTITY="Apple Development"
```

## Getting Help

1. **Check the workflow logs** for the exact certificate name being used
2. **Verify your Apple Developer account** has the right certificates
3. **Test locally first** before pushing to GitHub
4. **Use the debugging output** from the updated workflow

## Quick Fix Checklist

- [ ] Certificate is Developer ID Application type
- [ ] Certificate is not expired
- [ ] Certificate matches your Team ID
- [ ] p12 file was exported correctly
- [ ] Base64 conversion worked
- [ ] GitHub secrets are set correctly
- [ ] Team ID in secrets matches certificate

## Next Steps

1. Run the export script to get a fresh certificate
2. Update the GitHub secrets
3. Test with a new tag
4. Check the workflow logs for the debugging output 