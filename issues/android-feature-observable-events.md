# Android: Missing Feature — Observable Events (Observers Tab)

## Platform
Android

## Feature Description
The Observers tab allows users to register live observers on Ditto collections and see real-time document change events as they occur. Each observer monitors a DQL query and fires whenever matching documents are inserted, updated, or deleted, displaying the event stream in a live list.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/Tabs/ObserversTabView.swift` — Main observers tab UI
- `SwiftUI/Edge Debug Helper/Data/Repositories/ObservableRepository.swift` — Actor-based repository managing observer registration and event diffing
- `SwiftUI/Edge Debug Helper/Views/MainStudioView.swift` — Hosts Observers in the sidebar navigation

## Current Android Status
The sidebar shows an "OBSERVERS" section and the FAB menu has an "Observer" button. However, `StudioNavItem.OBSERVERS` routes to a "Coming Soon" placeholder — no live event monitoring UI exists.

## Expected Behavior
- User can register a new observer by specifying a DQL query and collection
- Active observers are listed with their query and status
- When documents change, events appear in a live-updating event list
- Each event shows: event type (insert/update/delete), document ID, timestamp, and changed document data
- User can remove/stop an observer
- Event detail view shows the full document diff

## Key Implementation Notes
- Ditto Android SDK: use `ditto.store.registerObserver(query)` or `ditto.store.execute(...).observe {...}`
- Events should be collected as a Flow/StateFlow in the ViewModel
- The SwiftUI `ObservableRepository` uses diffing to detect insert/update/delete — similar logic needed
- UI: list of observers on the left, event detail on the right (or stacked on phone)
- Consider using `LazyColumn` with animated insertions for the event stream

## Acceptance Criteria
- [ ] "Coming Soon" placeholder replaced with real Observers UI
- [ ] User can add a new observer with a DQL query
- [ ] Active observers are listed with query and status
- [ ] Live events appear in real-time as documents change
- [ ] Each event shows type (insert/update/delete), document ID, and timestamp
- [ ] Tapping an event shows full document data
- [ ] User can delete/stop an observer
- [ ] Observers persist within the session
