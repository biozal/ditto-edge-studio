import SwiftUI

/// First-run onboarding panel for a freshly-opened Ditto database.
///
/// Mirrors the VSCode extension's `WelcomePanel` (see
/// `~/Developer/ditto-vsc-es/webview-ui/welcome/welcome-element.ts`)
/// but the call-to-action sequence is adapted: VSCode's welcome opens
/// when the user has *no databases configured*, while this one opens
/// when a database is *already open* but has no subscriptions and no
/// query history. The 3-step walkthrough therefore points at
/// "add a subscription / query your data / visualize the mesh" rather
/// than "register a database".
///
/// Triggers:
///   - Help menu → Welcome (always shows)
///   - Auto-shown by `MainStudioViewModel.performLoad` when the active
///     database is fresh and `@AppStorage("showWelcomeOnNewDatabase")`
///     is true (the default).
struct WelcomeView: View {
    @AppStorage("showWelcomeOnNewDatabase") private var showWelcomeOnNewDatabase = true

    // Scale the hero badge with the user's Dynamic Type setting so the icon
    // never feels cramped relative to the surrounding scaled text.
    @ScaledMetric(relativeTo: .largeTitle) private var heroBadgeSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 32

    /// Caller-provided dismiss closure. macOS uses
    /// `Environment(\.dismissWindow)`; iPadOS uses a Binding<Bool>
    /// on the presenting sheet. The view stays agnostic.
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                whatIsDitto
                features
                getStarted
                userGuide
                quickstarts
                learnMore
                footer
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.dittoYellow)
                        .frame(width: heroBadgeSize, height: heroBadgeSize)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: heroIconSize, weight: .bold))
                        .foregroundStyle(Color.black)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Ditto Edge Studio")
                        .font(.largeTitle.weight(.semibold))
                    Text("A quick tour of what this app does and how to get the most out of your Ditto database.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Divider()
        }
    }

    // MARK: - What is Ditto?

    private var whatIsDitto: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What is Ditto?")
                .font(.title2.weight(.semibold))
            Text(
                "Ditto is a peer-to-peer, offline-first database. Apps that embed the Ditto SDK sync data " +
                    "directly with each other over Bluetooth LE, peer-to-peer Wi-Fi, and local LAN — no internet " +
                    "required. When a network is available, devices can also sync to the Ditto cloud " +
                    "(the \"Big Peer\") for durability and global reach."
            )
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

            QuoteBlock {
                Text(
                    "The mesh keeps working when Wi-Fi goes down, devices roam in and out of range, or the " +
                        "cloud is unreachable. Every device holds a full replica of the data it cares about, and " +
                        "conflicts are resolved automatically using CRDTs — no merge UI, no lost writes."
                )
            }

            ExternalLink(title: "About Ditto", url: "https://docs.ditto.live/home/about-ditto")
        }
    }

    // MARK: - Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What this app does")
                .font(.title2.weight(.semibold))
            Text(
                "Ditto Edge Studio is a control panel for your Ditto databases — inspect their live state, " +
                    "manage subscriptions, run DQL queries, and move data in and out without ever leaving the app."
            )
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

            FeatureGrid(features: WelcomeView.featureList)
        }
    }

    static let featureList: [WelcomeFeature] = [
        WelcomeFeature(
            title: "Multiple databases",
            body: "Register every Ditto database you work with — dev, staging, prod — and switch between them with one click."
        ),
        WelcomeFeature(
            title: "DQL Query Editor",
            body: "Run Ditto Query Language statements with history, favorites, and EXPLAIN plans. Page through large result sets without locking up the UI."
        ),
        WelcomeFeature(
            title: "Subscriptions",
            body: "Manage the queries that keep data flowing to this device. Import existing subscriptions from any peer that's already configured."
        ),
        WelcomeFeature(
            title: "Presence Graph",
            body: "Visualise the live mesh in real time: every connected peer, the transports they're using (LAN, Bluetooth, AWDL, WebSocket), and how data is routing through them."
        ),
        WelcomeFeature(
            title: "Query & Database Metrics",
            body: "Per-database dashboards that surface query execution plans, recent run history, and storage breakdown by collection — handy for diagnosing slow queries or runaway disk usage."
        ),
        WelcomeFeature(
            title: "Import & Export",
            body: "Move JSON datasets between collections, peers, or environments. Export the entire result of a query (not just the visible page) to a portable JSON file."
        ),
        WelcomeFeature(
            title: "Attachments",
            body: "Add, fetch, preview, and save binary attachments (images, audio, video, PDFs) right from the query results."
        ),
        WelcomeFeature(
            title: "Logging",
            body: "Live and historical SDK logs, app logs, transport conditions, and connection requests — filtered by level, source, and date range. Export to a folder for bug reports."
        )
    ]

    // MARK: - Get Started

    private var getStarted: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get started in three steps")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                StepRow(
                    number: 1,
                    title: "Add your first subscription",
                    details:
                    "Subscriptions are the queries that pull data from the Ditto cloud (and your peers) " +
                        "down to this device. Open the Subscriptions sidebar and click Add Subscription. " +
                        "Without at least one, your local replica stays empty."
                ) {
                    ExternalLink(title: "About subscriptions", url: "https://docs.ditto.live/sdk/latest/sync/syncing-data")
                }
                Divider()
                StepRow(
                    number: 2,
                    title: "Explore your data",
                    details:
                    "Switch the sidebar picker to Query (the macpro icon) to write DQL against any " +
                        "collection in this database. Results appear immediately in the detail pane — use " +
                        "the Raw / Table toggle below to switch views."
                ) {
                    ExternalLink(title: "DQL reference", url: "https://docs.ditto.live/dql/dql")
                }
                Divider()
                StepRow(
                    number: 3,
                    title: "Visualise the mesh",
                    details:
                    "The Subscriptions tab includes a Presence Graph view that draws every connected " +
                        "peer in real time. Useful for confirming peers see each other and identifying which " +
                        "transports (LAN, Bluetooth, AWDL, WebSocket) are carrying data."
                ) {
                    ExternalLink(title: "Mesh Presence guide", url: "https://docs.ditto.live/sdk/latest/sync/using-mesh-presence")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - User Guide

    private var userGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deep-dive: the User Guide")
                .font(.title2.weight(.semibold))
            Text(
                "Edge Studio ships with a comprehensive in-app User Guide covering every feature in " +
                    "detail — subscriptions, DQL syntax, the presence viewer, metrics dashboards, " +
                    "logging, attachments, imports/exports, and troubleshooting. It's the reference " +
                    "manual for the rest of the app and lives one menu click away."
            )
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            #if os(macOS)
            WelcomePrimaryButton(title: "Open User Guide", systemIcon: "book") {
                WindowController.openHelpWindow()
            }
            .padding(.top, 4)
            #endif
        }
    }

    // MARK: - Quickstarts

    private var quickstarts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try a quickstart in your favorite language")
                .font(.title2.weight(.semibold))
            QuoteBlock {
                Text(
                    "Edge Studio can download Ditto's official quickstart projects (Swift, Kotlin, " +
                        "Flutter, Rust, .NET, JavaScript, and more) onto your machine and pre-fill " +
                        "each project's .env file using this database's credentials — so the project " +
                        "is ready to build and run without copying any values by hand. The fastest " +
                        "way to see sync working end-to-end across a real client app."
                )
            }
            HStack(spacing: 16) {
                #if os(macOS)
                WelcomePrimaryButton(title: "Download Quickstarts…", systemIcon: "arrow.down.circle") {
                    WindowController.openQuickstartBrowserWindow()
                }
                #endif
                ExternalLink(title: "Browse on GitHub", url: "https://github.com/getditto/quickstart")
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Learn More

    private var learnMore: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Want more depth?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ExternalLink(title: "Ditto documentation", url: "https://docs.ditto.live/home/about-ditto")
                ExternalLink(title: "DQL reference", url: "https://docs.ditto.live/dql/dql")
                ExternalLink(title: "Mesh Presence guide", url: "https://docs.ditto.live/sdk/latest/sync/using-mesh-presence")
            }
            .font(.footnote)
        }
    }

    // MARK: - Footer (toggle + Close)

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
            HStack {
                Toggle("Show this screen when opening a new database", isOn: $showWelcomeOnNewDatabase)
                #if os(macOS)
                    .toggleStyle(.checkbox)
                #else
                    .toggleStyle(.switch)
                #endif
                    .font(.footnote)
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Feature Card Model + Grid

struct WelcomeFeature: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

private struct FeatureGrid: View {
    let features: [WelcomeFeature]
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(features) { feature in
                VStack(alignment: .leading, spacing: 8) {
                    Text(feature.title)
                        .font(.headline)
                    Text(feature.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Step Row

private struct StepRow<Trailing: View>: View {
    let number: Int
    let title: String
    let details: String
    @ViewBuilder let trailing: () -> Trailing

    /// Grow the number circle with Dynamic Type so the digit never clips at
    /// large accessibility text sizes.
    @ScaledMetric(relativeTo: .title3) private var circleSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.dittoYellow)
                    .frame(width: circleSize, height: circleSize)
                Text("\(number)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.black)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                trailing()
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Quote Block

private struct QuoteBlock<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.dittoYellow)
                .frame(width: 3)
            content()
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

// MARK: - External Link

/// Inline text link that opens via the platform's URL handler.
/// Wraps the `#if os(macOS)` / `#if os(iOS)` open call so the parent
/// view stays platform-agnostic.
private struct ExternalLink: View {
    let title: String
    let url: String

    var body: some View {
        Button {
            guard let url = URL(string: url) else { return }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary CTA Button

/// Yellow-tinted CTA button used inside the Welcome screen for
/// in-app actions (Open User Guide, Download Quickstarts…). Larger
/// than the sidebar empty-state buttons so it reads as the primary
/// action of its section. Mirrors `DittoYellowButton` in
/// `SidebarViews.swift` but isn't shared because the sidebar version
/// is `.caption`-sized for tight spaces.
private struct WelcomePrimaryButton: View {
    let title: String
    let systemIcon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.dittoYellow)
            )
        }
        .buttonStyle(.plain)
    }
}
