# Android: Missing Feature — Disk Usage Monitoring

## Platform
Android

## Feature Description
A dedicated view showing how much disk space the Ditto database is consuming. Users can see total database size and monitor storage growth. Useful for understanding the footprint of their Ditto deployment.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/Tools/` — Disk Usage tool view
- `SwiftUI/Edge Debug Helper/Data/Repositories/SystemRepository.swift` — Tracks disk usage metrics from the SDK

## Current Android Status
App Metrics view partially covers this — `AppMetricsViewModel` may include storage bytes as part of general metrics. However, there is no dedicated Disk Usage screen or tool. The feature is not surfaced prominently to the user.

## Expected Behavior
- Accessible from the Tools or Sync section
- Shows total Ditto database size in human-readable format (KB, MB, GB)
- Updates when navigating to the view
- Clear empty state if disk usage data is unavailable
- Shows the size of each collection in the database - important feature

## Key Implementation Notes
- Ditto Android SDK: check for `ditto.diskUsage` or equivalent property
- If storage bytes are already in `AppMetricsViewModel`, a dedicated screen can present this more prominently
- Consider placing in the Tools section alongside other system tools

## Acceptance Criteria
- [ ] Disk Usage is accessible from the app (Tools section or similar)
- [ ] Shows total database size in human-readable format
- [ ] Data is accurate and reflects current database size
- [ ] Refreshes when the view is opened
