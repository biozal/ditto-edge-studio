---
title: "Migrating a Real App to Swift 6: Data Races, a Dependency I Had to Evict, and the Compiler That Wouldn't Let Me Lie"
description: "What it actually took to move Ditto Edge Studio to Swift 6 strict concurrency — ripping out a dependency that wouldn't come along, taming 44 warnings, and the data race the compiler caught only after I told it to stop checking."
author: "Aaron LaBeau"
date: "2026-06-07"
tags: [swift, swift6, concurrency, swiftui, macos, ditto]
---

# Migrating a Real App to Swift 6: Data Races, a Dependency I Had to Evict, and the Compiler That Wouldn't Let Me Lie

Let me start with a confession: I have been writing concurrent code since the only tool in the box was a mutex and a prayer. I shipped threaded C++ when "thread safety" meant you'd personally audited every shared pointer at 2am. I did the `dispatch_async` dance through the whole GCD era. I have a decade of Swift behind me and a deeply earned suspicion of any code that touches two threads and claims to be fine.

So when Swift 6 showed up promising to *prove* my concurrency correct at compile time, I had two reactions at once. The grizzled half of me said "sure, kid." The other half — the half that has spent actual weekends chasing a heisenbug that only reproduced on a customer's M1 under sync load — said "...please. Please be real."

This is the story of moving **[Ditto Edge Studio](https://ditto.live)** — our SwiftUI debug-and-query tool for the Ditto edge database — to Swift 6's strict concurrency mode. It's a real app: SQLCipher persistence, an embedded MCP server, a SpriteKit presence graph, live sync over Bluetooth and WebSocket. Not a to-do list. The kind of app where concurrency bugs hide in the cracks and wait for a demo.

Spoiler: it was worth it. It was also more work than the WWDC talk implied, and the most valuable thing the compiler did happened in the *one* place I told it to stop looking. Let me show you.

---

## First, the Wall: A Dependency That Wasn't Coming to Swift 6

Here's the thing nobody warns you about. Swift 6 language mode isn't really a per-file setting. Your code can be immaculate — every actor isolated, every `Sendable` accounted for — and you'll still be stuck, because **one dependency that isn't Swift 6-ready can hold your entire module hostage.**

Mine was a code editor. I'd been using a popular SwiftUI editor package for the DQL query editor, and it transitively pulled in a syntax-highlighting library. Both were lovely. Both were also written for a more innocent time, and neither was going to compile under Swift 6 strict concurrency without upstream changes that weren't happening on my timeline.

I had the usual three options, and I want to be honest about how tempting the cowardly ones were:

1. **Pin the dependency and leave the whole app at Swift 5.** Free today, expensive forever.
2. **Fork it and fix it myself.** Now I own a syntax highlighter. I do not want to own a syntax highlighter.
3. **Evict it.** Rip it out, replace it with something that *did* speak Swift 6, and eat the cost once.

I went with eviction. (You knew I would. There's no blog post in "I pinned a version and went to lunch.")

The replacement was [HighlightSwift](https://github.com/appstefan/highlightswift) for the actual highlighting, wrapped in a hand-rolled editor I called `DQLCodeEditor` — an `NSViewRepresentable` on macOS, `UIViewRepresentable` on iPad, with a `@MainActor` coordinator doing debounced highlighting. The shape that matters looks like this:

```swift
@MainActor
final class Coordinator: NSObject, NSTextViewDelegate {
    private let highlighter = Highlight()
    private var highlightTask: Task<Void, Never>?

    func scheduleHighlight(_ source: String) {
        highlightTask?.cancel()
        highlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))   // debounce
            guard !Task.isCancelled else { return }
            await self?.applyHighlight(source)
        }
    }

    // Swift 6.2's isolated deinit: cancel the task on the main actor,
    // safely, without the old "capture self in a detached Task" hack.
    isolated deinit {
        highlightTask?.cancel()
    }
}
```

That `isolated deinit` is a small thing that made me genuinely happy. For years, cleaning up a `@MainActor` object's resources in `deinit` meant an awkward little ritual — you couldn't touch main-actor state from a nonisolated `deinit`, so you'd capture and bounce through a `Task`, and hope the timing worked out. Swift 6.2 just... lets the deinit be isolated. Twenty years of teardown footguns, quietly retired.

**The lesson, branded into me at this point:** in the Swift 6 world, your dependency graph is part of your concurrency story. Audit it *first*. The day you decide to flip the language mode is the wrong day to discover a transitive dependency from 2021 is the thing standing between you and a clean build.

---

## Flipping the Switch (and the 44 Warnings I Earned)

With the editor evicted, I changed the two settings that start the real work:

```
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
```

Then I built. The compiler thought about it for a moment and handed me **44 warnings.**

Now, I'd told everyone this app was production-ready. And here was the compiler, politely, with a list. Forty-four reasons it disagreed. There's a particular flavor of humility in shipping something you're proud of and then having a tool you respect say "that's nice, here are four dozen places you're racing." I deserved it. Strict concurrency doesn't care about your feelings or your changelog.

The warnings sorted into a few honest buckets:

- **Bridge code talking to `@MainActor` frameworks** — SpriteKit scenes, AppKit views, AVFoundation capture — where I'd been implicitly assuming the main thread for a decade and the compiler now wanted me to *say so.*
- **Deprecated `String(cString:)` overloads** that strict mode finally surfaced.
- **My own freshly-written code**, because of course. The refactor that removed the editor introduced its own crop.
- **Tests** — `@MainActor`-isolated helpers being called from nonisolated test bodies.

Driving that to zero — on both macOS *and* iPad, because the platforms disagree about API availability in ways that will absolutely catch you if you only build one — was the bulk of the migration. Not glamorous. Just a methodical march through every warning, asking the same question each time: *what is the actual isolation here, and how do I tell the compiler the truth?*

---

## The Cast of Characters You'll Actually Meet

Swift 6 concurrency has a vocabulary, and after a few hundred warnings you stop reading it as syntax and start reading it as *intent*. Here's the working developer's field guide to the ones that earned their keep.

### `@MainActor` — the one you already half-knew
Most of it was uncontroversial: view models, UI glue, anything touching AppKit/UIKit. Mark it, move on. The interesting cases were the SpriteKit scene and the SpriteKit layers, which the SDK now annotates `@MainActor` for you — so the fix was often *deleting* a `DispatchQueue.main.async` I'd written years ago out of superstition. Which brings me to a small joy:

```swift
// Before: GCD hop, written when "the main thread" was a vibe, not a type.
DispatchQueue.main.async { [weak self] in
    self?.onZoomChanged?(newScale)
}

// After: the scene is already @MainActor. Just... call it.
onZoomChanged?(newScale)
```

Ten years of reflexive `DispatchQueue.main.async`, and the compiler can now tell me when I'm already there. I deleted three of those. Each deletion felt like paying off a tiny debt I'd forgotten I owed.

### `nonisolated` — for the code that was never the problem
A surprising amount of "concurrency" friction is just pure functions trapped inside isolated types. I had a `timeLabel(execNs:planTotalExecNs:)` formatter living on a SwiftUI `View` (so, `@MainActor` by inheritance), and my tests — correctly nonisolated — couldn't call it. The honest fix wasn't to drag the tests onto the main actor. It was to admit the function had no business being isolated in the first place:

```swift
// It takes two Int64s and returns a String. There is no actor here.
nonisolated static func timeLabel(execNs: Int64?, planTotalExecNs: Int64) -> String? { ... }
```

`nonisolated` is the compiler letting you say "this was never shared state, stop worrying about it." Used well, it's not an escape hatch — it's documentation.

### `@unchecked Sendable` — the loaded gun (we'll come back to this)
Some types genuinely cross actor boundaries but can't *prove* their safety to the compiler — an `@Observable` reference type with mutable storage, say. For those you can write `@unchecked Sendable` and take the wheel yourself. I did, for my database-config model, with a contract written in a doc comment so Future Me couldn't claim ignorance:

```swift
/// `@unchecked Sendable` contract: instances are mutated only on the
/// `@MainActor` (the editors). Once handed to an actor, a config is a
/// read-only snapshot — actors read, never write. The mutate phase and the
/// read phase never overlap for a given instance, so it's race-free in
/// practice even though the compiler can't prove it.
@Observable
final class DittoConfigForDatabase: Codable, @unchecked Sendable { ... }
```

Write that comment. Write it every single time. Hold that thought — it's the whole moral of this post.

### The supporting cast
- **`isolated deinit`** (shown above): teardown on the owning actor, finally.
- **`MainActor.assumeIsolated { ... }`** for callbacks you *know* land on main but the compiler doesn't — e.g. a `NotificationCenter` observer registered with `queue: .main`. You're asserting a fact, not dodging a check.
- **`nonisolated(unsafe)`** — the "trust me" annotation for a non-`Sendable` static you swear is only touched serially. I used it on a couple of `ISO8601DateFormatter`s... and then, during review, replaced them with function-local instances instead. Because "I swear it's only touched serially" is exactly the sentence that precedes every concurrency incident report ever written. If you can make the escape hatch unnecessary, do.
- **`@preconcurrency import`** for frameworks (AVFoundation, the Ditto SDK) that predate `Sendable` annotations — a clean way to say "I'll adopt their guarantees when they ship them" without a sea of warnings.

---

## The Bug the Compiler Caught by *Not* Checking

Here's the part I actually want you to remember, because it's the part the conference talks gloss over.

Strict concurrency found a lot. But the single most dangerous bug in the codebase was in the *one place I had opted out of the checking* — behind `@unchecked Sendable`.

Remember that database-config model with the carefully-worded contract: *mutated only on the `@MainActor`?* My embedded MCP server — the bit that lets an AI agent query the database over HTTP — has a tool that reconfigures transports. And it did this:

```swift
// MCPToolHandlers.configureTransport — a plain `static func ... async`,
// reached from the NWConnection callback. NOT on the main actor.
config.isBluetoothLeEnabled = newBluetooth
config.isLanEnabled        = newLan
config.isAwdlEnabled       = newAwdl
```

Read that again with the contract in mind. The config is `@unchecked Sendable` *specifically because* I promised to only mutate it on the main actor. And here, in code reached from a network callback running who-knows-where, I was writing to it off the main actor — racing every SwiftUI view that reads those same properties. A real, honest-to-goodness data race, in production, in the exact shape I'd built a whole compile-time system to prevent.

The compiler said nothing. It *couldn't*. I'd shown it `@unchecked Sendable` and it had taken me at my word, like a gentleman.

The fix is trivial once you see it:

```swift
await MainActor.run {
    config.isBluetoothLeEnabled = newBluetooth
    config.isLanEnabled        = newLan
    config.isAwdlEnabled       = newAwdl
}
```

But the *finding* didn't come from the compiler. It came from a deliberate audit of every `@unchecked Sendable` and `nonisolated(unsafe)` in the codebase — the precise set of places where I'd told the checker to look away. (Same audit turned up an `NWConnection` keep-alive task with an unsynchronized `var`, fixed with an honest `NSLock`, and those GCD hops in the SpriteKit scene.)

**This is the lesson that's worth the whole migration:** Swift 6 doesn't make data races impossible. It makes them *rare and located.* It shrinks the universe of "anywhere" down to "the handful of spots where I explicitly signed a waiver." After thirty years of races that could be literally anywhere, that's not a small thing — that's the whole game. Your `@unchecked Sendable`s and your `nonisolated(unsafe)`s are now your threat model. Grep for them. Re-read them. Treat every one as a place a bug is allowed to live, because it is.

---

## What It Cost Me (Being Honest)

- **A dependency and a weekend.** Evicting the editor and writing `DQLCodeEditor` was real work that produced zero new features for the user. Migrations are like that.
- **Verbosity, occasionally.** `@escaping @MainActor @Sendable (...) -> Void` is a closure type that looks like a stack trace. It's correct. It is not pretty.
- **The temptation of the escape hatch.** Every time strict mode got loud, `@unchecked Sendable` whispered that it could make the noise stop. Resisting that — solving the actual isolation instead of muting the warning — is the discipline the whole thing demands.

## What It Bought Me

- **A real race fixed**, plus a latent one, plus a pile of GCD cruft deleted.
- **Isolation made explicit.** My code now *says* where it runs. New contributors (and Future Me) read intent instead of guessing.
- **A bounded threat model.** Concurrency bugs can now only hide in the spots I marked unsafe. I can audit those in an afternoon.
- **`isolated deinit` and friends** quietly erasing patterns I'd carried since the GCD days.

---

## So, Should You Migrate?

If any of these describe you, yes:

- You ship an app where **two things happen at once** and the cost of getting it wrong is a customer incident, not a failed unit test.
- You're willing to **audit your dependencies first** — and evict the one that won't make the trip.
- You can adopt the right mindset: **`@unchecked Sendable` is a promise you're personally keeping**, not a button that makes warnings go away.

If you're a solo dev on a single-threaded toy, Swift 5 will keep being lovely and nobody will arrest you. But for anything real, anything that syncs or streams or talks to the network on a background queue while a human stares at a SwiftUI view? Pay the toll. Flip the switch. Let the compiler tell you the truth you didn't want to hear.

I've been chasing data races since before some of you were typing. For the first time in my career, a tool handed me a *finite list* of the places one could be hiding — and then made me sign for each exception by name. The grizzled half of me is impressed. The half that lost those weekends to heisenbugs is, quietly, a little emotional about it.

We live in weird, wonderful times.

---

## Links

- **Swift 6 migration guide:** [swift.org/migration](https://www.swift.org/migration/documentation/migrationguide/)
- **HighlightSwift:** [github.com/appstefan/highlightswift](https://github.com/appstefan/highlightswift)
- **Ditto:** [ditto.live](https://ditto.live)

*Now if you'll excuse me, I have a list of `@unchecked Sendable`s to go re-read. All of them. By name.*
