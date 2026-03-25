# Android: Missing Feature — Import Subscriptions via QR Code

## Platform
Android

## Feature Description
Users can import subscription configurations by scanning a QR code or reading a QR code image. This allows easy sharing of subscription setups between devices or team members.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/` — QR import/export for database and subscription configs
- The .NET version has QR code import/export for database configs as a fully implemented feature

## Current Android Status
The FAB menu has an "Import Subscriptions" button that closes the FAB but performs no action — QR code scanning or subscription import is not implemented.

## Expected Behavior
- Tapping "Import Subscriptions" offers options: scan QR code or pick image file
- Camera-based QR scanning decodes a subscription configuration
- Decoded subscription is added to the active subscriptions list
- User sees confirmation of what was imported
- Error shown if QR code is invalid or unrecognized format

## Key Implementation Notes
- Use CameraX or ML Kit Barcode Scanning for QR camera scanning
- Define a QR payload format that matches the iOS/desktop export format (coordinate with SwiftUI team on schema)
- The FAB "Import Subscriptions" button already exists — needs real handler
- Consider also supporting image-based QR reading (pick from gallery) for devices without camera access

## Acceptance Criteria
- [ ] "Import Subscriptions" FAB button triggers QR scan or file import flow
- [ ] Camera QR scan decodes a valid subscription configuration
- [ ] Decoded subscription is added to the subscriptions list
- [ ] Success confirmation shown after import
- [ ] Error shown for invalid/unrecognized QR codes
- [ ] QR format is compatible with the SwiftUI and .NET versions
