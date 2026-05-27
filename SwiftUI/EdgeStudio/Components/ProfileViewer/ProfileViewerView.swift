import SwiftUI

/// Profile tab content. Renders one of four states based on the
/// caller-supplied inputs:
///
///   1. `profile != nil`           → full card-style viewer (the
///                                   only state most users see).
///   2. Metrics off                → prominent "Profiling is turned
///                                   off — Open Settings (⌘,) and
///                                   toggle Collect Metrics" with a
///                                   one-tap Open Settings button.
///                                   This is the discovery hook for
///                                   the entire feature, so the copy
///                                   is pinned in `plans/dql-profile-feature.md`.
///   3. Last query was non-SELECT  → "Profiles are only captured for
///                                   SELECT statements."
///   4. No query run yet           → "Run a SELECT query to capture
///                                   an execution profile."
///
/// State precedence: metrics-off wins over non-SELECT wins over
/// no-query-yet. If metrics is off the user can't fix anything by
/// re-running, so we tell them about the Setting first.
struct ProfileViewerView: View {
    let profile: QueryProfile?
    let metricsEnabled: Bool
    let lastQueryText: String

    /// Card vs Plan tree presentation. Persists for the lifetime of
    /// this view (resets when the parent re-mounts, e.g. on database
    /// switch). Default `.card` since the card list shows ALL the
    /// data; the Plan view is the higher-level "shape of the query"
    /// view that users open after they've spotted something
    /// interesting in the card list.
    @State private var planMode: PlanMode = .card

    enum PlanMode: String, CaseIterable {
        case card = "Card"
        case plan = "Plan"

        var icon: String {
            switch self {
            case .card: return "list.bullet.rectangle"
            case .plan: return "rectangle.connected.to.line.below"
            }
        }
    }

    var body: some View {
        ScrollView {
            content
                .padding(16)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let profile {
            populated(profile: profile)
        } else if !metricsEnabled {
            metricsOffState
        } else if !lastQueryText.isEmpty, !QueryService.isSelectStatement(lastQueryText) {
            nonSelectState
        } else {
            noQueryYetState
        }
    }

    private func populated(profile: QueryProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileQueryHeaderCard(profile: profile)
            ProfileSummaryStrip(profile: profile)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text("EXECUTION PLAN")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("View mode", selection: $planMode) {
                        ForEach(PlanMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                switch planMode {
                case .card:
                    ProfileCardListView(root: profile.plan)
                case .plan:
                    ProfilePlanTreeView(
                        root: profile.plan,
                        totalElapsedNs: profile.times.elapsedNs
                    )
                }
            }

            ProfileFooterStrip(profile: profile)
            badgeLegend
        }
    }

    // MARK: - Empty states

    /// The headline state. Pinned copy per the plan — this is how
    /// users discover the feature, so the wording explicitly names
    /// the keyboard shortcut and the toggle label.
    private var metricsOffState: some View {
        EmptyStateBlock(
            icon: "speedometer",
            title: "Profiling is turned off",
            bodyText:
            "Profiles are captured automatically when **Collect Metrics** is enabled. " +
                "Open the Settings window (⌘,) and toggle **Collect Metrics** on, then re-run " +
                "your query to see the execution plan here."
        ) {
            openSettingsButton
        }
    }

    private var nonSelectState: some View {
        EmptyStateBlock(
            icon: "list.bullet.indent",
            title: "Profile is only captured for SELECT statements",
            bodyText:
            "Ditto's `PROFILE` keyword only supports `SELECT`. Run a SELECT query to " +
                "capture an execution plan here. INSERT, UPDATE, DELETE, and EVICT have no profile."
        )
    }

    private var noQueryYetState: some View {
        EmptyStateBlock(
            icon: "list.bullet.indent",
            title: "Run a query to capture a profile",
            bodyText:
            "Type a `SELECT` statement in the editor above and click Run. " +
                "Edge Studio will capture an execution plan and display it here."
        )
    }

    /// The Open Settings button is macOS-only — Settings on iPadOS
    /// is a different surface (per-app settings inside the system
    /// Settings app), and `SettingsLink` is macOS-only too. iPadOS
    /// users see the headline + body but no button, which still
    /// tells them what to do.
    @ViewBuilder
    private var openSettingsButton: some View {
        #if os(macOS)
        SettingsLink {
            Label("Open Settings…", systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.dittoYellow)
                )
        }
        .buttonStyle(.plain)
        #endif
    }

    /// Footer legend block — explains what each colored badge means.
    /// Mirrors the "How to read this page" callout at the bottom of
    /// `screens/profile-viewer.png` so users don't have to guess at
    /// `recv` vs `send`.
    private var badgeLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)
            Text("Reading the badges")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                legendRow("in", "documents flowing in", color: .blue)
                legendRow("out", "documents flowing out", color: .green)
                legendRow("exec", "CPU time inside this operator", color: .red)
                legendRow("recv", "time waiting on upstream operators", color: .orange)
                legendRow("send", "time pushing output downstream", color: .purple)
            }
        }
    }

    private func legendRow(_ label: String, _ description: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.15)))
                .frame(width: 56, alignment: .center)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shared visual scaffold for the three empty states. Centered,
/// large SF Symbol, headline, body copy with selective markdown
/// bolding, optional action button below.
///
/// NOTE on the `bodyText` field name: SwiftUI's `View` protocol
/// requires a property called `body`, so we can't store the body
/// copy in a stored property of the same name. `bodyText` keeps the
/// stored prop and the SwiftUI body view textually distinct.
private struct EmptyStateBlock<Action: View>: View {
    let icon: String
    let title: String
    /// Body copy. Markdown is rendered via `AttributedString` so
    /// `**Collect Metrics**` shows up bold without requiring a Text
    /// concatenation jungle at every call site.
    let bodyText: String
    @ViewBuilder let primaryAction: () -> Action

    init(
        icon: String,
        title: String,
        bodyText: String,
        @ViewBuilder primaryAction: @escaping () -> Action
    ) {
        self.icon = icon
        self.title = title
        self.bodyText = bodyText
        self.primaryAction = primaryAction
    }

    /// Convenience for empty states with no action button. Specialises
    /// `Action` to `EmptyView` so the trailing-closure overload above
    /// stays unambiguous.
    init(
        icon: String,
        title: String,
        bodyText: String
    ) where Action == EmptyView {
        self.icon = icon
        self.title = title
        self.bodyText = bodyText
        primaryAction = { EmptyView() }
    }

    private var bodyAttributed: AttributedString {
        // `.inlineOnlyPreservingWhitespace` keeps **bold**/`code` working
        // while ignoring URL parsing and list syntax — the body strings
        // here are hand-authored so we don't want surprises.
        (try? AttributedString(markdown: bodyText, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(bodyText)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(bodyAttributed)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
            primaryAction()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
