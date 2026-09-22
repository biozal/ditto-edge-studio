# iPhone Duo toolbar remediation

## Findings and confirmation

| Finding | Confirmations | Evidence |
| --- | --- | --- |
| The parent `NavigationSplitView` and Presence detail both declare sidebar, sync, and close toolbar items, producing duplicate sidebar chrome on iPhone Duo. | 2 | Author inspection: `MainStudioView.swift` and `DetailViews.swift`, plus all four supplied screenshots. Independent review: `/root/duo_ui_review`, 2026-09-21. |
| Transport settings is a content-header button, so it cannot participate in Duo's system action rail. | 2 | Author inspection and independent review of `DetailViews.swift` and `TransportSettingsButton.swift`; open/closed Presence screenshots. |
| The viewer’s `.bottomBar` contains a custom `HStack`, preventing its controls from adapting as independent native toolbar items and competing with the connection counter. | 2 | Author inspection and independent review of `DetailViews.swift` and `PresenceViewerSK.swift`; viewer screenshots. |
| Presence actions use a mixture of cancellation, primary, and bottom-bar placements. Duo consequently renders separate top-left, top-right, upper-rail, and lower-rail clusters. | 2 | Author comparison of `es-presence-open.png` and `es-presence-closed.png` with placement call sites; independent review by `/root/duo_ui_review`, 2026-09-21. |
| The Studio creation/import menu is a custom yellow button at the bottom of the sidebar, and database creation is a custom FAB/hero CTA rather than native toolbar content. | 2 | Author inspection of `MainStudioView.swift` and `ContentView.swift`; independent review by `/root/duo_ui_review`, 2026-09-21. |
| In the compact Presence header, the peer search is centered against the full picker-and-title stack rather than the picker, leaving the two controls on visibly different baselines. | 2 | Author inspection of `es-presence-closed.png` and `DetailViews.swift`; independent review by `/root/duo_ui_review`, 2026-09-21. |
| Inspector is a `.secondaryAction` on Duo, forcing it into overflow even when its trailing rail has capacity. | 2 | Author inspection of `MainStudioView.swift`; independent review by `/root/duo_ui_review`, 2026-09-21. |
| Passive metric/log details keep NavigationSplitView’s automatic compact `<` while also supplying the explicit Sidebar action, rendering two controls that open the same sidebar. | 2 | Author inspection of `MainStudioView.swift`; independent review by `/root/duo_ui_review`, 2026-09-21. |
| Logs Analyzer places its operational controls in a custom content header and its display status and Clear action in a floating bottom overlay. The overlay obscures the closed Duo display and neither group can participate in the system action rail. | 2 | Author inspection of `LoggingDetailView.swift` and `logs-closed.png`; independent pre-change review by `/root/duo_ui_review`, 2026-09-21. |
| Presence declares Sync, Close, and Inspector before its Transport Config, transport-count, and Viewer Controls actions, so the workspace controls interrupt the requested contextual action sequence. The same trio is repeated in Query, Observation, passive details, and the macOS root toolbar. | 2 | Author inspection of `MainStudioView.swift` and `DetailViews.swift`; independent review by `/root/duo_ui_review`, 2026-09-22. Source inspection cannot prove SwiftUI’s final cross-hierarchy rail merge order. |
| Logs Analyzer receives Add, its Info / Log Actions items, and the workspace trio from three independently attached iOS toolbar modifiers. SwiftUI merges those hierarchies, so their source order cannot define the requested sequence. | 2 | Author inspection of `MainStudioView.swift` and `LoggingDetailView.swift`; independent review by `/root/duo_ui_review`, 2026-09-22. |

Apple’s iPhone Duo guidance requires toolbar content to be attached to a navigation
container’s detail column, provides the shared vertical bar there, and recommends
symbol-backed semantic items that the system can arrange or overflow.

## Implementation batches

1. Make each detail view the sole owner of its iOS toolbar and show the sidebar
   affordance only while split-view navigation is collapsed.
2. Promote Transport Settings from the Presence header to a native detail toolbar
   item, using its title and symbol for vertical-bar and overflow representations.
3. Replace the Presence viewer’s custom bottom-bar cluster with one native Viewer
   Controls menu, keeping the connection counter as an independent trailing item.
4. Use native toolbar actions for Studio creation/import and database creation on
   iPhone, iPad, and macOS; remove the custom sidebar-plus, FAB, and hero CTA.
5. Give Duo 27.1 a single trailing-action policy: workspace controls prefer the
   vertical rail, including Inspector when capacity permits, and Close is a
   workspace action rather than a leading cancellation control.
6. Use a custom picker-center alignment guide for the compact Presence header;
   keep peer search outside `ViewThatFits` to preserve its update-performance
   boundary.
7. Hide NavigationSplitView’s automatic compact back affordance once at the shared
   detail container, leaving the explicit Sidebar toolbar action as the sole
   sidebar-opening control.
8. On iOS, replace the Logs Analyzer’s custom header and bottom overlay with a
   native `Log Actions` toolbar menu and a separate Info toolbar action. Preserve
   SDK level, refresh, pause/resume, pattern manager, and destructive clear;
   present the former display-status label from Info. Keep the macOS layout.
9. Centralize the persistent workspace controls in a trailing `Sync`, `Close`,
   `Inspector` toolbar bundle. Declare that bundle after each detail’s contextual
   actions; on Presence, Transport Config, transport count, and Viewer Controls
   precede it. Keep Query and Observation pagination bottom bars separate.
10. Give the iOS Logs route one toolbar declaration: compact Sidebar, Add, Log
    Info, Log Actions, then the shared Sync / Close / Inspector workspace bundle.
    Exclude Logs from the parent Add toolbar and its passive-detail toolbar;
    retain the macOS Logs header, footer, and window toolbar.

## Verification record

The production call sites were inspected after each batch. The initial non-author
review by `/root/duo_ui_review` verified that the iOS root toolbar is absent and the
compact-only sidebar gate is wired at each detail call site. Its independent
post-consolidation review verified the native Studio and database Add actions, the
single Viewer Controls menu, the absence of iOS Presence `.bottomBar` actions, and
the 27.1 vertical-rail policy for Sync, Close, transport, connection status, and
Inspector.

The following checks passed:

- `rtk git diff --check`
- macOS Debug build of the `Edge Studio` scheme
- iOS Debug generic-device build without code signing
- iPhone Duo 27.1 simulator build (independent review)
- `EdgeStudioUnitTests` on macOS

The broad macOS `test` command ran the unit suite successfully (166 tests), then
Xcode timed out enabling UI-test automation. That is an environment failure; UI
automation and the user path remain unverified.

The picker-alignment change also passes current macOS and generic iOS Debug builds.
`/root/duo_ui_review` independently verified both picker branches and the search
field publish the same guide while the dynamic search leaf remains outside
`ViewThatFits`. Its actual closed-Duo pixel alignment is still runtime-unverified.

Inspector is now an iOS 27.1 `.primaryAction` with `.verticalPreferred`; the
non-author post-fix review verified the pre-27.1 and macOS paths are unchanged.

The shared compact-detail back-button rule passes the generic iOS Debug build.
`/root/duo_ui_review` independently verified that it covers every passive detail
destination without removing the explicit Sidebar action. Its runtime appearance is
still unverified.

The Logs Analyzer iOS implementation passes the generic iOS and macOS Debug builds
using isolated DerivedData paths, plus an independent iOS Simulator Debug build
(only the pre-existing AppIntents metadata-skip warning). Its non-author post-change
review verified the production selection path, removal of `toolbarRow` and
`footerRow` from the iOS hierarchy, preservation of the macOS layout, and the Info
/ `Log Actions` wiring. The native menu retains SDK level, refresh, pause/resume,
patterns, and destructive Clear; Info presents the former footer status. A
closed-Duo runtime capture, final rail ordering, and accessibility traversal remain
unverified; no visual conformance is claimed yet.

The toolbar-order batch passes isolated generic-iOS and macOS Debug builds and the
default signed macOS test run (885 passing tests, no failures). The discarded macOS
unit-test invocation with `CODE_SIGNING_ALLOWED=NO` is invalid on this machine:
macOS rejected its unsigned `DittoSwift.framework` at launch, before app code ran.
Its non-author post-change review verified that Presence
declares contextual actions before the shared workspace trio, Query compact and
regular, Observation, passive details, and macOS all use that trio, and Query /
Observation bottom bars remain unchanged. Real Duo captures still remain required:
Add belongs to a parent toolbar, so SwiftUI’s merge and system overflow behavior—not
source order alone—determines final cross-hierarchy rail order and visibility.

The Logs-order batch replaces its three merged iOS toolbars with one ordered builder.
Its non-author post-change review verified Sidebar (when compact), Add, Log Info, Log
Actions, then Sync / Close / Inspector; the outer Add toolbar excludes Logs and no
passive workspace toolbar remains on that route. macOS retains its existing Logs
header/footer and root toolbar. The batch passes macOS Debug and generic iOS Debug
compilation, plus the signed macOS test run (885 passing tests). The resulting Duo
vertical-rail and system-overflow presentation remain runtime-visual validation items.

The earlier closed (cover-display) simulator capture showed the Viewer controls on
the trailing system bar, but the newer supplied open/closed screenshots identified
the remaining fragmentation from mixed placement semantics. The revised layout needs
a new, non-destructive Duo cover-and-inner pose capture before visual conformance,
exact rail ordering, overflow, and accessibility traversal can be claimed.

This batch deliberately does not alter the existing Query and Observer custom bottom
toolbar groups. They need a follow-up Duo audit before claiming whole-app toolbar
conformance.
