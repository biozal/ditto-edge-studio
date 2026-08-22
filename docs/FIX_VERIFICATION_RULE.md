# The Two-Reviewer Rule (mandatory)

**Do not fix a reported problem until at least two independent reviewers have
confirmed it exists.** Do not claim a fix is complete until a reviewer that did not
write the fix has verified it in the code.

This rule is not process for its own sake. It exists because a documented sequence of
"fix everything found" rounds on this repository made the product **worse**, three
times, in ways the author asserted were fixed:

| What was claimed | What was actually true |
|---|---|
| "QR sharing excludes advanced settings — enforced on encode and decode" | `QRCodeGenerator.swift` had never been touched. The change had *introduced* sync-scope sharing over QR, and `sanitizedForSharing()` was called only from a unit test. |
| "Editing a sensitive value revokes its acknowledgement" | `setParameter`/`setValue`/`setType` had **zero production callers**. The editor bindings wrote the model directly. Five passing tests certified a security control the shipping UI bypassed. |
| "Restored `.completeFileProtection` on the SQLCipher key file" | True, and it created an iPadOS path that **destroys every stored credential**: a locked background relaunch cannot read the now-protected key, and the pre-existing `catch` regenerates and overwrites it. The hardening was more dangerous than the gap. |

The pattern in every case: a fix was written, asserted as done, and the assertion was
false or incomplete. Reviewers caught it — but only *after* more code had been layered
on top.

---

## The rule, precisely

### 1. Two independent confirmations before any fix

A finding is **actionable** only when two reviewers who did not consult each other
report it. One reviewer's finding is a *hypothesis*.

- Reviewers must be given the code and the claims, not each other's output.
- The author's own verification counts as **one** confirmation, and only when it is
  evidence-based (a command run, a file read, a test executed) — never "I believe I
  fixed that".
- A finding with one source goes to a **second, targeted adjudication round** before
  any code changes. Adjudication reviewers must be told the finding is disputed and
  asked to confirm *or refute* it with file:line evidence.

### 2. Never fix an unconfirmed finding

Single-source findings are recorded as **unconfirmed** and left alone. Acting on them
is how speculative churn enters the codebase. If a single-source finding is severe
enough that leaving it is unacceptable, run the adjudication round *first* — that is
cheaper than a wrong fix plus its rollback.

### 3. Refutation is a valid, valuable outcome

A reviewer that disproves a finding has done useful work. Record refuted findings and
the evidence, so the same hypothesis is not re-litigated next round. Not every
reported problem is real: reviewers over-report, and some findings are pre-existing
behavior working as intended.

### 4. The author never signs off their own fix

After fixing, a reviewer that did not write the change verifies:

- the fix is **wired up** — grep for production call sites, not just definitions;
- the tests exercise the **shipping path**, not a parallel method the UI bypasses;
- the fix did not **introduce** a worse failure than the one it closed.

"It compiles and the tests pass" is not verification. Both were true of every failure
in the table above.

### 5. Separate *is this broken?* from *is this shippable?*

Run readiness review as its own pass, with its own reviewers, after the fixes settle.
Mixing "find bugs" with "ship or not" produces neither.

---

## Required workflow

```
   report ──► 2+ independent reviewers
                    │
        ┌───────────┴───────────┐
    confirmed              single-source
        │                       │
        │                 adjudication round
        │                  ┌────┴────┐
        │              confirmed   refuted ──► record, do not fix
        ▼                  ▼
      ┌──── fix (smallest change that closes it) ────┐
      │                                              │
      ▼                                              ▼
  verify wiring (grep call sites)            verify no new failure
      │                                              │
      └──────────► independent verification ◄─────────┘
                            │
                    readiness review (separate pass)
```

## Anti-patterns this rule bans

- **Fix-by-assertion.** Writing a method and declaring the behavior fixed without
  grepping for a caller. Every fix that touches behavior must name its call site.
- **Tests aimed at the fix instead of the feature.** If a test calls a view-model
  method the view does not use, it proves nothing. Test the path the user takes.
- **Batch fixing a long review list in one pass.** Fatigue is when wiring gets
  missed. Fix in small batches, verify each.
- **Hardening without a threat trace.** Before adding a security control, trace what
  else reads the thing you are protecting. `.completeFileProtection` was correct in
  isolation and destructive in context.
- **Claiming clean tooling without running it on the changed files.** `swiftlint` used to
  exclude the test targets, so "lint clean" was true of the config and false of the code.
  `.swiftlint.yml` now lists all four targets — but its 142 test-code *warnings* still mean
  a green build proves only "zero errors". Run it on your changed files, by path, at
  `--strict`.

## What to write down

For every round, record in the plan or PR:

- each finding, its **confirmation count**, and the reviewer evidence;
- findings deliberately **not** fixed, and why;
- for each fix, the **production call site** that now uses it;
- claims that are **unverified** rather than verified — with what would verify them.

Unverified is an acceptable state to ship. Unverified *described as verified* is not.
